# Sending QSOs to RUMlogNG — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every QSO logged, edited or deleted in a contest log reaches RUMlogNG at once as N1MM's UDP contact packets, with a paced "send the whole log" catch-up on ⇧⌘L — so contest files never need importing by hand.

**Architecture:** Three units wired by the window. `LogDocument` reports each row mutation as a `QSOChange` through one observer closure (undo rides along for free). `N1MMContactBroadcast` (Core/Export, pure) turns a change into N1MM `contactinfo` / `contactreplace` / `contactdelete` XML from the row, the log and its `ContestDefinition`. `QSOBroadcaster` (App, `@MainActor @Observable`) holds the preferences, a lazily opened `UDPSending` socket, one paced send queue and the inline status the toolbar popover shows.

**Tech Stack:** Swift 6, SwiftUI + Observation, BSD sockets via the existing `UDPSender`, XCTest. Build/test with `xcodegen generate` + `xcodebuild` (CLAUDE.md). Spec: `docs/superpowers/specs/2026-09-07-rumlog-qso-broadcast-design.md`. Sources: `docs/research/n1mm-udp-contactinfo.md`.

**Guardrails:** no party- or radio-specific branching in `Sources/UI/`; every new file needs `xcodegen generate` before the commit (the pbxproj is tracked); never rebuild or test while a copy of the app is running (`pgrep -fl QSOPartyLogger` first); README features, keyboard table and test count ship in the last commit; golden corpus and export fixtures must not change.

---

## File structure

| File | Responsibility |
| --- | --- |
| `Sources/Core/Models/QSOChange.swift` (new) | The mutation value the document reports: added / removed / replaced rows |
| `Sources/App/LogDocument.swift` (modify) | `qsoObserver` closure, called by the four row mutations |
| `Sources/Core/Export/N1MMContactBroadcast.swift` (new) | N1MM packet XML from `(QSO, ContestLog, ContestDefinition)`; `packets(for:)`, `wholeLog(...)` |
| `Sources/Hardware/Network/UDPSender.swift` (modify) | `SO_BROADCAST`; error text no longer says "audio stream" |
| `Sources/App/AppSettings.swift` (modify) | `qsoBroadcastEnabled` / `qsoBroadcastHost` / `qsoBroadcastPort` |
| `Sources/App/QSOBroadcaster.swift` (new) | Config, socket lifecycle, paced queue, whole-log send, status |
| `Sources/UI/KeyMonitorGate.swift`, `KeyDiagnostics.swift`, `ShortcutHint.swift` (modify) | ⇧⌘L |
| `Sources/UI/QSOBroadcastPane.swift` (new) | The popover |
| `Sources/UI/MainView.swift` (modify) | Toolbar button, observer wiring, `.onChange`, `perform` |
| `Tests/App/LogDocumentTests.swift`, `Tests/Core/N1MMContactBroadcastTests.swift`, `Tests/App/QSOBroadcasterTests.swift`, `Tests/App/QSOBroadcastPreferenceTests.swift`, `Tests/App/KeyMonitorGateTests.swift`, `Tests/App/ShortcutHintsTests.swift` | Tests |
| `README.md`, `docs/PROVENANCE.md`, `project.yml`, `Resources/Info.plist` | Docs |

---

### Task 1: `QSOChange` and the document's observer seam

**Files:**
- Create: `Sources/Core/Models/QSOChange.swift`
- Modify: `Sources/App/LogDocument.swift` (mutations, ~:175-240)
- Test: `Tests/App/LogDocumentTests.swift` (append at the end of the class)

- [ ] **Step 1.1: Write the failing tests** — add inside `LogDocumentTests`:

```swift
    // MARK: The row-change seam (RUMlogNG broadcast, 2026-09-07)

    @MainActor
    private func observedDocument() -> (LogDocument, () -> [QSOChange]) {
        let doc = LogDocument()
        var seen: [QSOChange] = []
        doc.qsoObserver = { seen.append($0) }
        return (doc, { seen })
    }

    private func row(_ call: String, county: String = "MRN") -> QSO {
        QSO(timestampUTC: Date(timeIntervalSince1970: 1_770_000_000), call: call, band: .m20,
            modeClass: .cw, rawMode: "CW", rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: county)
    }

    @MainActor
    func testAppendReportsTheRowsAdded() {
        let (doc, seen) = observedDocument()
        let rows = [row("W0BH"), row("N0XYZ")]
        doc.append(qsos: rows, undoManager: nil)
        XCTAssertEqual(seen(), [.added(rows)])
    }

    @MainActor
    func testAppendingNothingReportsNothing() {
        let (doc, seen) = observedDocument()
        doc.append(qsos: [], undoManager: nil)
        XCTAssertEqual(seen(), [])
    }

    @MainActor
    func testRemoveReportsTheRowsRemovedAndRemoveGroupTheWholeGroup() {
        let (doc, seen) = observedDocument()
        let a = row("W0BH"), b = row("N0XYZ")
        var c1 = row("K5TR"), c2 = row("K5TR", county: "BOU")
        c2.groupID = c1.groupID
        doc.append(qsos: [a, b, c1, c2], undoManager: nil)
        doc.remove(ids: [b.id], undoManager: nil)
        doc.removeGroup(groupID: c1.groupID, undoManager: nil)
        XCTAssertEqual(seen().dropFirst().map { $0 }, [.removed([b]), .removed([c1, c2])])
    }

    @MainActor
    func testRemovingAnUnknownIDReportsNothing() {
        let (doc, seen) = observedDocument()
        doc.remove(ids: [UUID()], undoManager: nil)
        XCTAssertEqual(seen(), [])
    }

    @MainActor
    func testUpdateReportsOldAndNew() {
        let (doc, seen) = observedDocument()
        let old = row("W0BH")
        doc.append(qsos: [old], undoManager: nil)
        var new = old
        new.theirLoc = "BOU"
        doc.update(qso: new, undoManager: nil)
        XCTAssertEqual(seen().last, .replaced([.init(old: old, new: new)]))
    }

    @MainActor
    func testBulkUpdateReportsEveryPairOnceAndSkipsRowsNotInTheLog() {
        let (doc, seen) = observedDocument()
        let a = row("W0BH"), b = row("N0XYZ")
        doc.append(qsos: [a, b], undoManager: nil)
        var a2 = a, b2 = b
        a2.rstRcvd = "579"; b2.rstRcvd = "559"
        doc.update(qsos: [a2, b2, row("K5TR")], actionName: "Change 2 Contacts", undoManager: nil)
        XCTAssertEqual(seen().last, .replaced([.init(old: a, new: a2), .init(old: b, new: b2)]))
    }

    @MainActor
    func testUndoReportsTheInverseChange() {
        let (doc, seen) = observedDocument()
        let undo = UndoManager()
        undo.groupsByEvent = false
        let a = row("W0BH")
        undo.beginUndoGrouping()
        doc.append(qsos: [a], undoManager: undo)
        undo.endUndoGrouping()
        undo.undo()
        XCTAssertEqual(seen(), [.added([a]), .removed([a])])
        undo.redo()
        XCTAssertEqual(seen().last, .added([a]))
    }

    /// Opening a file sets the log outright; nothing must re-send it.
    @MainActor
    func testLoadingALogReportsNothing() throws {
        let (doc, seen) = observedDocument()
        var log = ContestLog(partyID: "ksqp")
        log.qsos = [row("W0BH")]
        doc.log = try LogDocument.decodeUpgrading(try log.encoded())
        XCTAssertEqual(seen(), [])
    }
```

- [ ] **Step 1.2: Run to verify it fails**

Run: `xcodegen generate && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/LogDocumentTests 2>&1 | tail -5`
Expected: build error — `QSOChange` and `qsoObserver` undefined.

- [ ] **Step 1.3: Create `Sources/Core/Models/QSOChange.swift`**

```swift
import Foundation

/// One mutation of a log's rows, as `LogDocument` reports it to whoever is
/// listening (`LogDocument.qsoObserver`) — today the RUMlogNG broadcaster.
/// Carries exactly the rows the mutation touched, so a listener never diffs
/// the log. Undo and redo re-enter the same mutations and so report the
/// inverse change through the same seam; opening a document reports
/// nothing, because nothing was done to it.
enum QSOChange: Equatable, Sendable {
    /// One edited row: what it was, and what it is now. The id is the same.
    struct Replacement: Equatable, Sendable {
        let old: QSO
        let new: QSO
        init(old: QSO, new: QSO) {
            self.old = old
            self.new = new
        }
    }

    case added([QSO])
    case removed([QSO])
    case replaced([Replacement])
}
```

- [ ] **Step 1.4: Modify `LogDocument`** — add the property after `scoreSnapshotProvider`:

```swift
    /// Whoever wants to hear about row changes — the RUMlogNG broadcaster —
    /// receives each mutation with the rows it touched (`QSOChange`). Undo
    /// and redo come back through the same four mutations, so a ⌘Z of a
    /// logged contact reports `.removed` with no extra code. Loading a
    /// document sets `log` directly and reports nothing. Nil until the
    /// window wires it, so a document built in a test tells no one.
    @ObservationIgnored var qsoObserver: ((QSOChange) -> Void)?
```

and report from the four mutations — `append` (after `setActionName`):

```swift
        if !qsos.isEmpty { qsoObserver?(.added(qsos)) }
```

`remove` (after `setActionName`):

```swift
        if !removed.isEmpty { qsoObserver?(.removed(removed)) }
```

`update(qso:)` (after `setActionName`):

```swift
        qsoObserver?(.replaced([.init(old: old, new: qso)]))
```

`update(qsos:actionName:)` — collect pairs in the loop and report after `setActionName`:

```swift
        var previous: [QSO] = []
        var replacements: [QSOChange.Replacement] = []
        for idx in log.qsos.indices {
            guard let updated = byID[log.qsos[idx].id] else { continue }
            previous.append(log.qsos[idx])
            replacements.append(.init(old: log.qsos[idx], new: updated))
            log.qsos[idx] = updated
        }
        guard !previous.isEmpty else { return }
        …
        undoManager?.setActionName(actionName)
        qsoObserver?(.replaced(replacements))
```

- [ ] **Step 1.5: Run to verify it passes**

Run: the same command. Expected: `LogDocumentTests` all pass, `** TEST SUCCEEDED **`.

- [ ] **Step 1.6: Commit** (with Task 2 and 3 — one core commit; see Task 3 Step 3.5).

---

### Task 2: `N1MMContactBroadcast` — the packets

**Files:**
- Create: `Sources/Core/Export/N1MMContactBroadcast.swift`
- Test: `Tests/Core/N1MMContactBroadcastTests.swift` (new)

- [ ] **Step 2.1: Write the failing tests**

```swift
import XCTest
@testable import QSOPartyLogger

/// N1MM's contact packets, field for field from N1MM's own page
/// (docs/research/n1mm-udp-contactinfo.md), built from a log row the way
/// the ADIF exporter builds a record. One packet is pinned byte for byte.
final class N1MMContactBroadcastTests: XCTestCase {

    let t = Date(timeIntervalSince1970: 1_788_013_920)  // 2026-08-29 14:32:00Z
    let station = N1MMContactBroadcast.Station(stationName: "SHACK-MAC")

    func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-4000-8000-%012X", n))! }

    func ksqp() throws -> ContestDefinition { try XCTUnwrap(ContestCatalog.contest(id: "ksqp")) }

    func ksqpLog(_ rows: [QSO]) -> ContestLog {
        var log = ContestLog(partyID: "ksqp")
        log.station.callsign = "KE5CW"
        log.myLocation = .outOfState(location: "TX")
        log.qsos = rows
        return log
    }

    func w0bh(freq: Int? = 14042, rawMode: String = "CW", mode: ModeClass = .cw) -> QSO {
        QSO(id: id(1), timestampUTC: t, call: "W0BH", band: .m20, modeClass: mode, rawMode: rawMode,
            freqKHz: freq, rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: "MRN")
    }

    // MARK: The packet, byte for byte

    func testAKSQPRowIsN1MMsContactInfoPacket() throws {
        let row = w0bh()
        let packet = N1MMContactBroadcast.contactInfo(
            row: row, log: ksqpLog([row]), contest: try ksqp(), station: station,
            scoring: .init(points: 2, isNewMultiplier: true))
        XCTAssertEqual(packet.kind, .info)
        XCTAssertEqual(packet.call, "W0BH")
        XCTAssertEqual(packet.xml, """
            <?xml version="1.0" encoding="utf-8"?>
            <contactinfo>
            \t<app>QSOPartyLogger</app>
            \t<contestname>KS-QSO-PARTY</contestname>
            \t<contestnr>1</contestnr>
            \t<timestamp>2026-08-29 14:32:00</timestamp>
            \t<mycall>KE5CW</mycall>
            \t<band>14</band>
            \t<rxfreq>1404200</rxfreq>
            \t<txfreq>1404200</txfreq>
            \t<operator>KE5CW</operator>
            \t<mode>CW</mode>
            \t<call>W0BH</call>
            \t<countryprefix>K</countryprefix>
            \t<wpxprefix>W0</wpxprefix>
            \t<stationprefix>KE5CW</stationprefix>
            \t<continent>NA</continent>
            \t<snt>599</snt>
            \t<sntnr>0</sntnr>
            \t<rcv>599</rcv>
            \t<rcvnr>0</rcvnr>
            \t<gridsquare></gridsquare>
            \t<exchange1>MRN</exchange1>
            \t<section></section>
            \t<comment></comment>
            \t<qth></qth>
            \t<name></name>
            \t<power></power>
            \t<misctext></misctext>
            \t<zone>0</zone>
            \t<prec></prec>
            \t<ck>0</ck>
            \t<ismultiplier1>1</ismultiplier1>
            \t<ismultiplier2>0</ismultiplier2>
            \t<ismultiplier3>0</ismultiplier3>
            \t<points>2</points>
            \t<radionr>1</radionr>
            \t<run1run2>1</run1run2>
            \t<RoverLocation></RoverLocation>
            \t<RadioInterfaced>1</RadioInterfaced>
            \t<NetworkedCompNr>0</NetworkedCompNr>
            \t<IsOriginal>True</IsOriginal>
            \t<NetBiosName></NetBiosName>
            \t<IsRunQSO>0</IsRunQSO>
            \t<StationName>SHACK-MAC</StationName>
            \t<ID>00000000000040008000000000000001</ID>
            \t<IsClaimedQso>1</IsClaimedQso>
            \t<oldtimestamp>2026-08-29 14:32:00</oldtimestamp>
            \t<oldcall>W0BH</oldcall>
            \t<SentExchange>TX</SentExchange>
            \t<dxcc>291</dxcc>
            \t<my_gridsquare></my_gridsquare>
            </contactinfo>
            """)
        XCTAssertEqual(packet.data, Data(packet.xml.utf8))
    }

    // MARK: Field rules

    func testBandTokensAreTheLowerEdgeInMegahertz() {
        let expected: [Band: String] = [
            .m160: "1.8", .m80: "3.5", .m60: "5.3", .m40: "7", .m30: "10", .m20: "14", .m17: "18",
            .m15: "21", .m12: "24", .m10: "28", .m6: "50", .m2: "144", .cm125: "222", .cm70: "420",
        ]
        for band in Band.allCases {
            XCTAssertEqual(N1MMContactBroadcast.bandToken(band), expected[band], band.rawValue)
        }
    }

    func testFrequencyIsInTensOfHertzAndARowWithoutCATTakesTheBandDefault() {
        XCTAssertEqual(N1MMContactBroadcast.frequencyTens(w0bh(freq: 14042)), 1_404_200)
        XCTAssertEqual(N1MMContactBroadcast.frequencyTens(w0bh(freq: 7040)), 704_000)
        XCTAssertEqual(N1MMContactBroadcast.frequencyTens(w0bh(freq: nil)), Band.m20.defaultFreqKHz * 100)
    }

    func testARowWithoutCATSaysTheRadioWasNotInterfaced() throws {
        let row = w0bh(freq: nil)
        let xml = N1MMContactBroadcast.contactInfo(row: row, log: ksqpLog([row]), contest: try ksqp(), station: station).xml
        XCTAssertTrue(xml.contains("<RadioInterfaced>0</RadioInterfaced>"))
        XCTAssertTrue(xml.contains("<rxfreq>1404000</rxfreq>"))
    }

    /// N1MM's vocabulary has USB and LSB but no SSB: the sideband follows
    /// the frequency, the rule the radio path uses (`BandPlan`).
    func testSSBResolvesToTheBandsSidebandAndOtherModesPassThrough() {
        XCTAssertEqual(N1MMContactBroadcast.mode(w0bh(freq: 14250, rawMode: "SSB", mode: .phone)), "USB")
        var forty = w0bh(freq: 7180, rawMode: "SSB", mode: .phone); forty.band = .m40
        XCTAssertEqual(N1MMContactBroadcast.mode(forty), "LSB")
        var noCAT = w0bh(freq: nil, rawMode: "SSB", mode: .phone); noCAT.band = .m80
        XCTAssertEqual(N1MMContactBroadcast.mode(noCAT), "LSB")
        XCTAssertEqual(N1MMContactBroadcast.mode(w0bh(rawMode: "usb", mode: .phone)), "USB")
        XCTAssertEqual(N1MMContactBroadcast.mode(w0bh(rawMode: "RTTY", mode: .digital)), "RTTY")
        XCTAssertEqual(N1MMContactBroadcast.mode(w0bh(rawMode: "FT8", mode: .digital)), "FT8")
    }

    func testTimestampIsN1MMsFormatInUTC() {
        XCTAssertEqual(N1MMContactBroadcast.timestamp(t), "2026-08-29 14:32:00")
        XCTAssertEqual(N1MMContactBroadcast.timestamp(Date(timeIntervalSince1970: 0)), "1970-01-01 00:00:00")
    }

    func testIDIsTheRowsUUIDAsThirtyTwoLowerCaseHexCharacters() {
        let uuid = UUID(uuidString: "F9FFAC4F-CD3E-479C-A86E-137DF1338531")!
        XCTAssertEqual(N1MMContactBroadcast.id(uuid), "f9ffac4fcd3e479ca86e137df1338531")
        XCTAssertEqual(N1MMContactBroadcast.id(uuid).count, 32)
    }

    func testTextIsXMLEscaped() throws {
        var row = w0bh()
        row.notes = "Tom & Jerry <QRP> \"long\" 'path'"
        let xml = N1MMContactBroadcast.contactInfo(row: row, log: ksqpLog([row]), contest: try ksqp(), station: station).xml
        XCTAssertTrue(xml.contains("<comment>Tom &amp; Jerry &lt;QRP&gt; &quot;long&quot; &apos;path&apos;</comment>"), xml)
    }

    func testRunPostureAndTheEnginesCreditAreCarried() throws {
        var row = w0bh()
        row.posture = .run
        let xml = N1MMContactBroadcast.contactInfo(row: row, log: ksqpLog([row]), contest: try ksqp(), station: station,
                                                   scoring: .init(points: 3, isNewMultiplier: false)).xml
        XCTAssertTrue(xml.contains("<IsRunQSO>1</IsRunQSO>"))
        XCTAssertTrue(xml.contains("<points>3</points>"))
        XCTAssertTrue(xml.contains("<ismultiplier1>0</ismultiplier1>"))
    }

    func testADXCallWithNoCTYMatchLeavesTheEntityElementsEmpty() throws {
        var row = w0bh()
        row.call = "QQ9ZZZ"
        let xml = N1MMContactBroadcast.contactInfo(row: row, log: ksqpLog([row]), contest: try ksqp(), station: station).xml
        XCTAssertTrue(xml.contains("<countryprefix></countryprefix>"))
        XCTAssertTrue(xml.contains("<continent></continent>"))
        XCTAssertTrue(xml.contains("<dxcc></dxcc>"))
    }

    // MARK: Exchange shapes

    func testSerialsAndTheReceivedTokenForCQP() throws {
        let contest = try XCTUnwrap(ContestCatalog.contest(id: "cqp"))
        var log = ContestLog(partyID: "cqp")
        log.station.callsign = "KE5CW"
        log.myLocation = .outOfState(location: "TX")
        let row = QSO(id: id(2), timestampUTC: t, call: "N6XYZ", band: .m20, modeClass: .cw, rawMode: "CW",
                      freqKHz: 14042, rstSent: "599", rstRcvd: "599", serialSent: 12, serialRcvd: 7,
                      myLoc: "TX", theirLoc: "SCLA")
        log.qsos = [row]
        let xml = N1MMContactBroadcast.contactInfo(row: row, log: log, contest: contest, station: station).xml
        XCTAssertTrue(xml.contains("<sntnr>12</sntnr>"))
        XCTAssertTrue(xml.contains("<rcvnr>7</rcvnr>"))
        XCTAssertTrue(xml.contains("<exchange1>SCLA</exchange1>"))
        XCTAssertTrue(xml.contains("<SentExchange>TX</SentExchange>"))
    }

    func testTheNameGoesToNameAndTheSentExchangeCarriesNameAndState() throws {
        let contest = try XCTUnwrap(ContestCatalog.contest(id: "naqpcw"))
        var log = ContestLog(partyID: "naqpcw", exchangeName: "TOM")
        log.station.callsign = "KE5CW"
        log.myLocation = .outOfState(location: "TX")
        let row = QSO(id: id(3), timestampUTC: t, call: "W0BH", band: .m20, modeClass: .cw, rawMode: "CW",
                      freqKHz: 14042, rstSent: "599", rstRcvd: "599", nameSent: "TOM", nameRcvd: "BOB",
                      myLoc: "TX", theirLoc: "CA")
        log.qsos = [row]
        let xml = N1MMContactBroadcast.contactInfo(row: row, log: log, contest: contest, station: station).xml
        XCTAssertTrue(xml.contains("<name>BOB</name>"))
        XCTAssertTrue(xml.contains("<exchange1>CA</exchange1>"))
        XCTAssertTrue(xml.contains("<SentExchange>TOM TX</SentExchange>"), xml)
    }

    /// The member-or-power element: a power goes to `power` ("received power
    /// exchange from the other station"); a member number is not a power.
    func testAReceivedPowerGoesToPowerAndAMemberNumberDoesNot() throws {
        let contest = try XCTUnwrap(ContestCatalog.contest(id: "skeeter"))
        var log = ContestLog(partyID: "skeeter", exchangeMember: "13")
        log.station.callsign = "KE5CW"
        log.myLocation = .outOfState(location: "TX")
        let qrp = QSO(id: id(4), timestampUTC: t, call: "K3WWP", band: .m20, modeClass: .cw, rawMode: "CW",
                      freqKHz: 14060, rstSent: "599", rstRcvd: "599", memberSent: "13", memberRcvd: "5W",
                      myLoc: "TX", theirLoc: "PA")
        let member = QSO(id: id(5), timestampUTC: t, call: "W2LJ", band: .m20, modeClass: .cw, rawMode: "CW",
                         freqKHz: 14060, rstSent: "599", rstRcvd: "599", memberSent: "13", memberRcvd: "1",
                         myLoc: "TX", theirLoc: "NJ")
        log.qsos = [qrp, member]
        let qrpXML = N1MMContactBroadcast.contactInfo(row: qrp, log: log, contest: contest, station: station).xml
        XCTAssertTrue(qrpXML.contains("<power>5W</power>"), qrpXML)
        let memberXML = N1MMContactBroadcast.contactInfo(row: member, log: log, contest: contest, station: station).xml
        XCTAssertTrue(memberXML.contains("<power></power>"), memberXML)
    }

    /// A general contest's elements by kind: section, precedence, check,
    /// zone, grid, class, power — built from the CQ WW CW fixture with the
    /// exchange swapped, so no bundle has to carry a Sweepstakes.
    func generalContest(exchange: [[String: Any]]) throws -> ContestDefinition {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "cqwwcw", withExtension: "json"))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        json["exchange"] = exchange
        json["id"] = "general-test"
        return try JSONDecoder().decode(ContestDefinition.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testAGeneralContestsElementsLandByKind() throws {
        let contest = try generalContest(exchange: [
            ["id": "rst", "kind": "rst", "sentBy": ["all": [:]]],
            ["id": "nr", "kind": "serial", "sentBy": ["all": [:]]],
            ["id": "prec", "kind": "precedence", "sentBy": ["all": [:]]],
            ["id": "ck", "kind": "check", "sentBy": ["all": [:]]],
            ["id": "section", "kind": "token", "sentBy": ["all": [:]]],
            ["id": "zone", "kind": "cqZone", "sentBy": ["all": [:]]],
            ["id": "grid", "kind": "grid", "sentBy": ["all": [:]]],
            ["id": "class", "kind": "classToken", "sentBy": ["all": [:]]],
            ["id": "pwr", "kind": "power", "sentBy": ["all": [:]]],
        ])
        var log = ContestLog(partyID: contest.id)
        log.station.callsign = "KE5CW"
        log.station.gridLocator = "DM95"
        let row = QSO(id: id(6), timestampUTC: t, call: "W1AW", band: .m40, modeClass: .cw, rawMode: "CW", freqKHz: 7040,
                      sent: ["rst": "599", "nr": "12", "prec": "A", "ck": "88", "section": "WTX", "zone": "4", "grid": "DM95", "class": "1D", "pwr": "100"],
                      rcvd: ["rst": "579", "nr": "345", "prec": "B", "ck": "71", "section": "CT", "zone": "5", "grid": "FN31", "class": "2A", "pwr": "5"])
        log.qsos = [row]
        let xml = N1MMContactBroadcast.contactInfo(row: row, log: log, contest: contest, station: station).xml
        XCTAssertTrue(xml.contains("<snt>599</snt>"))
        XCTAssertTrue(xml.contains("<rcv>579</rcv>"))
        XCTAssertTrue(xml.contains("<sntnr>12</sntnr>"))
        XCTAssertTrue(xml.contains("<rcvnr>345</rcvnr>"))
        XCTAssertTrue(xml.contains("<prec>B</prec>"))
        XCTAssertTrue(xml.contains("<ck>71</ck>"))
        XCTAssertTrue(xml.contains("<section>CT</section>"))
        XCTAssertTrue(xml.contains("<zone>5</zone>"))
        XCTAssertTrue(xml.contains("<gridsquare>FN31</gridsquare>"))
        XCTAssertTrue(xml.contains("<exchange1>2A</exchange1>"), xml)
        XCTAssertTrue(xml.contains("<power>5</power>"))
        XCTAssertTrue(xml.contains("<SentExchange>A 88 WTX 4 DM95 1D 100</SentExchange>"), xml)
        XCTAssertTrue(xml.contains("<my_gridsquare>DM95</my_gridsquare>"))
        XCTAssertTrue(xml.contains("<contestname>CQ-WW-CW</contestname>"))
    }

    func testAnITUZoneStandsInWhenThereIsNoCQZone() throws {
        let contest = try generalContest(exchange: [
            ["id": "rst", "kind": "rst", "sentBy": ["all": [:]]],
            ["id": "itu", "kind": "ituZone", "sentBy": ["all": [:]]],
        ])
        var log = ContestLog(partyID: contest.id)
        log.station.callsign = "KE5CW"
        let row = QSO(id: id(7), timestampUTC: t, call: "W1AW", band: .m20, modeClass: .cw, rawMode: "CW", freqKHz: 14042,
                      sent: ["rst": "599", "itu": "7"], rcvd: ["rst": "599", "itu": "8"])
        let xml = N1MMContactBroadcast.contactInfo(row: row, log: log, contest: contest, station: station).xml
        XCTAssertTrue(xml.contains("<zone>8</zone>"))
    }

    /// The callbook stamp fills only what the exchange left empty — the
    /// precedence ADIF uses.
    func testTheCallbookStampFillsNameQTHAndGridWhenTheExchangeHasNone() throws {
        var row = w0bh()
        row.callbook = .init(name: "Bob", qth: "Marion, KS", state: "KS", grid: "EM18", source: "QRZ")
        let xml = N1MMContactBroadcast.contactInfo(row: row, log: ksqpLog([row]), contest: try ksqp(), station: station).xml
        XCTAssertTrue(xml.contains("<name>Bob</name>"))
        XCTAssertTrue(xml.contains("<qth>Marion, KS</qth>"))
        XCTAssertTrue(xml.contains("<gridsquare>EM18</gridsquare>"))
    }

    // MARK: Replace and delete

    func testAReplaceCarriesTheOldCallAndTimeUnderItsOwnTag() throws {
        let old = w0bh()
        var new = old
        new.call = "W0BHX"
        new.timestampUTC = t.addingTimeInterval(60)
        let packet = N1MMContactBroadcast.contactReplace(row: new, replacing: old, log: ksqpLog([new]), contest: try ksqp(), station: station)
        XCTAssertEqual(packet.kind, .replace)
        XCTAssertEqual(packet.call, "W0BHX")
        XCTAssertTrue(packet.xml.hasPrefix("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<contactreplace>\n"))
        XCTAssertTrue(packet.xml.hasSuffix("</contactreplace>"))
        XCTAssertTrue(packet.xml.contains("<call>W0BHX</call>"))
        XCTAssertTrue(packet.xml.contains("<timestamp>2026-08-29 14:33:00</timestamp>"))
        XCTAssertTrue(packet.xml.contains("<oldcall>W0BH</oldcall>"))
        XCTAssertTrue(packet.xml.contains("<oldtimestamp>2026-08-29 14:32:00</oldtimestamp>"))
        XCTAssertTrue(packet.xml.contains("<ID>00000000000040008000000000000001</ID>"))
    }

    func testADeleteIsN1MMsEightElements() throws {
        let row = w0bh()
        let packet = N1MMContactBroadcast.contactDelete(row: row, log: ksqpLog([row]), station: station)
        XCTAssertEqual(packet.kind, .delete)
        XCTAssertEqual(packet.xml, """
            <?xml version="1.0" encoding="utf-8"?>
            <contactdelete>
            \t<app>QSOPartyLogger</app>
            \t<timestamp>2026-08-29 14:32:00</timestamp>
            \t<mycall>KE5CW</mycall>
            \t<band>14</band>
            \t<call>W0BH</call>
            \t<contestnr>1</contestnr>
            \t<StationName>SHACK-MAC</StationName>
            \t<ID>00000000000040008000000000000001</ID>
            </contactdelete>
            """)
    }

    // MARK: A change → packets

    func testAChangeBecomesPacketsInN1MMsOrder() throws {
        let contest = try ksqp()
        let a = w0bh()
        var b = w0bh(); b.id = id(2); b.call = "N0XYZ"
        var b2 = b; b2.theirLoc = "BOU"
        let log = ksqpLog([a, b2])
        let scoring: (QSO) -> N1MMContactBroadcast.RowScoring = { $0.call == "N0XYZ" ? .init(points: 4, isNewMultiplier: true) : .none }

        let added = N1MMContactBroadcast.packets(for: .added([a, b]), log: log, contest: contest, station: station, scoring: scoring)
        XCTAssertEqual(added.map(\.kind), [.info, .info])
        XCTAssertEqual(added.map(\.call), ["W0BH", "N0XYZ"])
        XCTAssertTrue(added[1].xml.contains("<points>4</points>"))

        let removed = N1MMContactBroadcast.packets(for: .removed([a]), log: log, contest: contest, station: station, scoring: scoring)
        XCTAssertEqual(removed.map(\.kind), [.delete])

        let replaced = N1MMContactBroadcast.packets(for: .replaced([.init(old: b, new: b2)]), log: log, contest: contest, station: station, scoring: scoring)
        XCTAssertEqual(replaced.map(\.kind), [.delete, .replace], "N1MM: a delete, then a replace")
        XCTAssertTrue(replaced[1].xml.contains("<exchange1>BOU</exchange1>"))
        XCTAssertTrue(replaced[1].xml.contains("<ismultiplier1>1</ismultiplier1>"))
    }

    func testTheWholeLogIsEveryRowOldestFirst() throws {
        let contest = try ksqp()
        let later = w0bh()
        var earlier = w0bh(); earlier.id = id(2); earlier.call = "N0XYZ"; earlier.timestampUTC = t.addingTimeInterval(-300)
        let packets = N1MMContactBroadcast.wholeLog(log: ksqpLog([later, earlier]), contest: contest, station: station, scoring: { _ in .none })
        XCTAssertEqual(packets.map(\.call), ["N0XYZ", "W0BH"])
        XCTAssertEqual(packets.map(\.kind), [.info, .info])
    }
}
```

- [ ] **Step 2.2: Run to verify it fails**

Run: `xcodegen generate && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/N1MMContactBroadcastTests 2>&1 | tail -5`
Expected: build error — `N1MMContactBroadcast` undefined.

- [ ] **Step 2.3: Create `Sources/Core/Export/N1MMContactBroadcast.swift`**

```swift
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
                contactReplace(row: pair.new, replacing: pair.old, log: log, contest: contest, station: station, scoring: scoring(pair.new)),
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
        let zone = firstNonEmpty(value(.cqZone, in: row.rcvd, contest: contest), value(.ituZone, in: row.rcvd, contest: contest))
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
    private static func value(_ kind: ExchangeElement.Kind, in map: [String: String], contest: ContestDefinition) -> String {
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
```

- [ ] **Step 2.4: Run to verify it passes**

Run: the same command. Expected: `N1MMContactBroadcastTests` pass, `** TEST SUCCEEDED **`. If `testAKSQPRowIsN1MMsContactInfoPacket` fails on `countryprefix`/`dxcc`, the cty table's values for W0BH are the ones to read from the failure message and confirm against `Resources/CTY` — never edit the code to make the pin pass.

---

### Task 3: `UDPSender` — `SO_BROADCAST`, general error text

**Files:**
- Modify: `Sources/Hardware/Network/UDPSender.swift` (`UDPError`, `init`)

- [ ] **Step 3.1: Change the error text** — the sender is no longer the audio stream's alone:

```swift
        var errorDescription: String? {
            switch self {
            case .resolve(let host):
                "Could not resolve \(host)."
            case .socket(let e), .connect(let e):
                "Could not open the UDP socket: \(String(cString: strerror(e)))"
            }
        }
```

- [ ] **Step 3.2: Set `SO_BROADCAST`** after the socket is created, before `connect` — with a comment:

```swift
        let s = socket(first.pointee.ai_family, first.pointee.ai_socktype, first.pointee.ai_protocol)
        guard s >= 0 else { throw UDPError.socket(errno) }
        // A subnet broadcast (192.168.1.255 — the addressing N1MM documents
        // for its contact packets) is refused by the kernel unless the
        // socket says it means to; harmless for a unicast destination.
        var broadcast: Int32 = 1
        _ = setsockopt(s, SOL_SOCKET, SO_BROADCAST, &broadcast, socklen_t(MemoryLayout<Int32>.size))
```

- [ ] **Step 3.3: Build and run the Flex driver tests** (they script the socket, so the change must not disturb them):

Run: `xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/FlexRadioDriverTests 2>&1 | tail -3`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 3.4: Update the design doc's `my_gridsquare` row** to say "empty when unset" (the element is always present).

- [ ] **Step 3.5: Commit Tasks 1–3**

```bash
pgrep -fl QSOPartyLogger || true   # must print nothing
xcodegen generate
git add Sources/Core/Models/QSOChange.swift Sources/Core/Export/N1MMContactBroadcast.swift Sources/App/LogDocument.swift Sources/Hardware/Network/UDPSender.swift Tests/App/LogDocumentTests.swift Tests/Core/N1MMContactBroadcastTests.swift QSOPartyLogger.xcodeproj/project.pbxproj docs/superpowers/specs/2026-09-07-rumlog-qso-broadcast-design.md docs/superpowers/plans/2026-09-07-rumlog-qso-broadcast.md docs/research/n1mm-udp-contactinfo.md
git commit -m "core: N1MM contact packets from a log row, and the document's row-change seam"
```

---

### Task 4: Preferences

**Files:**
- Modify: `Sources/App/AppSettings.swift` (after the callbook block; `init`)
- Test: `Tests/App/QSOBroadcastPreferenceTests.swift` (new)

- [ ] **Step 4.1: Write the failing tests**

```swift
import XCTest
@testable import QSOPartyLogger

/// The three preferences behind the RUMlog pane — off by default, RUMlogNG
/// on this Mac at N1MM's port, each under its own key, a bad port healed.
final class QSOBroadcastPreferenceTests: XCTestCase {

    private func scratchStore(seeding seed: [String: Any] = [:]) throws -> UserDefaults {
        let suiteName = "org.b5n.QSOPartyLogger.tests.qsobroadcast"
        UserDefaults().removePersistentDomain(forName: suiteName)
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suiteName) }
        let scratch = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        for (key, value) in seed { scratch.set(value, forKey: key) }
        return scratch
    }

    @MainActor
    func testAnEmptyStoreIsOffAndAimedAtRUMlogOnThisMac() throws {
        let settings = AppSettings(defaults: try scratchStore())
        XCTAssertFalse(settings.qsoBroadcastEnabled)
        XCTAssertEqual(settings.qsoBroadcastHost, "127.0.0.1")
        XCTAssertEqual(settings.qsoBroadcastPort, 12060)
        XCTAssertEqual(settings.qsoBroadcast, QSOBroadcaster.Config(enabled: false, host: "127.0.0.1", port: 12060))
    }

    @MainActor
    func testTheValuesPersistUnderTheirOwnKeys() throws {
        let scratch = try scratchStore()
        let settings = AppSettings(defaults: scratch)
        settings.qsoBroadcastEnabled = true
        settings.qsoBroadcastHost = "192.168.1.255"
        settings.qsoBroadcastPort = 12061
        XCTAssertEqual(scratch.object(forKey: "qsoBroadcastEnabled") as? Bool, true)
        XCTAssertEqual(scratch.string(forKey: "qsoBroadcastHost"), "192.168.1.255")
        XCTAssertEqual(scratch.object(forKey: "qsoBroadcastPort") as? Int, 12061)
        let reread = AppSettings(defaults: scratch)
        XCTAssertEqual(reread.qsoBroadcast, QSOBroadcaster.Config(enabled: true, host: "192.168.1.255", port: 12061))
    }

    @MainActor
    func testAStoredPortOutsideTheRangeFallsBackToN1MMs() throws {
        XCTAssertEqual(AppSettings(defaults: try scratchStore(seeding: ["qsoBroadcastPort": 0])).qsoBroadcastPort, 12060)
        XCTAssertEqual(AppSettings(defaults: try scratchStore(seeding: ["qsoBroadcastPort": 70000])).qsoBroadcastPort, 12060)
    }
}
```

- [ ] **Step 4.2: Run to verify it fails** — `-only-testing:QSOPartyLoggerTests/QSOBroadcastPreferenceTests`. Expected: build error, `qsoBroadcastEnabled` undefined.

- [ ] **Step 4.3: Add to `AppSettings`** (properties after `callbookPrimary`; the reads in `init` after `callbookPrimaryRaw`):

```swift
    // MARK: Sending QSOs to RUMlogNG (N1MM's UDP contact packets)

    /// Send every logged, edited and deleted QSO to RUMlogNG — or any
    /// N1MM-compatible listener — as it happens (`QSOBroadcaster`). Off by
    /// default: a logger never starts talking to another program unasked.
    var qsoBroadcastEnabled: Bool {
        didSet { defaults.set(qsoBroadcastEnabled, forKey: "qsoBroadcastEnabled") }
    }

    /// Where the packets go: RUMlogNG on this Mac by default; another Mac's
    /// address, or a subnet broadcast (`192.168.1.255`), reaches one
    /// elsewhere.
    var qsoBroadcastHost: String {
        didSet { defaults.set(qsoBroadcastHost, forKey: "qsoBroadcastHost") }
    }

    /// N1MM's recommended port, and RUMlogNG's "QSOs received from N1MM"
    /// default.
    var qsoBroadcastPort: Int {
        didSet { defaults.set(qsoBroadcastPort, forKey: "qsoBroadcastPort") }
    }

    static let defaultQSOBroadcastHost = "127.0.0.1"
    static let defaultQSOBroadcastPort = 12060
```

```swift
        qsoBroadcastEnabled = defaults.object(forKey: "qsoBroadcastEnabled") as? Bool ?? false
        qsoBroadcastHost = defaults.string(forKey: "qsoBroadcastHost") ?? Self.defaultQSOBroadcastHost
        // A port outside the range falls back to N1MM's rather than to
        // nothing: a hand-edited preference file must never leave the
        // sender with no destination.
        qsoBroadcastPort = (defaults.object(forKey: "qsoBroadcastPort") as? Int)
            .flatMap { (1...65535).contains($0) ? $0 : nil } ?? Self.defaultQSOBroadcastPort
```

The `qsoBroadcast` value the window pushes lives in `QSOBroadcaster.swift` (Task 5) as an `AppSettings` extension.

- [ ] **Step 4.4: Run to verify it passes** — after Task 5's file exists (the test names `QSOBroadcaster.Config`). Run both suites together at Step 5.4.

---

### Task 5: `QSOBroadcaster`

**Files:**
- Create: `Sources/App/QSOBroadcaster.swift`
- Test: `Tests/App/QSOBroadcasterTests.swift` (new)

- [ ] **Step 5.1: Write the failing tests**

```swift
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
        private(set) var closed = 0
        var refuse = false
        var sendFailures: (count: Int, lastErrno: Int32?) { lock.withLock { (failures, failures > 0 ? EHOSTUNREACH : nil) } }
        var sent: [Data] { lock.withLock { stored } }
        var sentXML: [String] { sent.map { String(decoding: $0, as: UTF8.self) } }
        func send(_ data: Data) {
            lock.withLock {
                if refuse { failures += 1 } else { stored.append(data) }
            }
        }
        func close() { lock.withLock { closed += 1 } }
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
        b.handle(.added(rows), log: log(rows), contest: ksqp, scoring: { $0.call == "W0BH" ? .init(points: 2, isNewMultiplier: true) : .none })
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
        var new = old; new.theirLoc = "BOU"
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
        let calls = f.sockets[0].sentXML.map { xml -> String in
            let start = xml.range(of: "<call>")!.upperBound
            return String(xml[start..<xml.range(of: "</call>")!.lowerBound])
        }
        XCTAssertEqual(calls, ["N0XYZ", "W0BH", "K5TR"])
        XCTAssertFalse(b.isSendingWholeLog)
        XCTAssertEqual(b.status, .sent(count: 3, lastCall: "K5TR", at: t0, destination: "127.0.0.1:12060"))
    }

    func testASecondPressStopsAWholeLogSendAndKeepsLiveChanges() async {
        let f = Factory()
        let b = broadcaster(f)
        b.pacing = .seconds(10)   // never reached in the test: the first packet goes, then it waits
        let rows = (1...5).map { row("K\($0)AA", at: Double($0)) }
        b.sendWholeLog(log: log(rows), contest: ksqp, scoring: noScore)
        b.handle(.added([row("W0BH")]), log: log(rows), contest: ksqp, scoring: noScore)
        b.sendWholeLog(log: log(rows), contest: ksqp, scoring: noScore)   // Stop
        XCTAssertFalse(b.isSendingWholeLog)
        b.pacing = .zero
        b.configure(.init(enabled: true, host: "127.0.0.1", port: 12061))  // reopen; the live packet is still queued
        await b.flush()
        let xml = f.sockets.flatMap(\.sentXML)
        XCTAssertTrue(xml.contains { $0.contains("<call>W0BH</call>") }, "the live change survives Stop")
        XCTAssertFalse(xml.contains { $0.contains("<call>K5AA</call>") }, "the tail of the whole-log send was dropped")
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
        b.pacing = .seconds(10)
        b.sendWholeLog(log: log([row("W0BH"), row("N0XYZ", at: 1)]), contest: ksqp, scoring: noScore)
        b.configure(.init(enabled: false, host: "127.0.0.1", port: 12060))
        await b.flush()
        XCTAssertEqual(b.status, .off)
        XCTAssertFalse(b.isSendingWholeLog)
        XCTAssertEqual(f.sockets.first?.closed, 1)
        XCTAssertLessThanOrEqual(f.sockets.first?.sent.count ?? 0, 1)
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
```

- [ ] **Step 5.2: Run to verify it fails** — `-only-testing:QSOPartyLoggerTests/QSOBroadcasterTests`. Expected: build error, `QSOBroadcaster` undefined.

- [ ] **Step 5.3: Create `Sources/App/QSOBroadcaster.swift`**

```swift
import Foundation
import Observation

/// Sends the log's changes to RUMlogNG — or any N1MM-compatible listener —
/// as N1MM contact packets over UDP (`N1MMContactBroadcast`), and keeps the
/// status line honest about what left this Mac. One per log window, like
/// the spot clients.
///
/// One paced queue carries everything: a live contact, a bulk edit's
/// hundreds of pairs, and a whole-log resend all leave one datagram at a
/// time with `pacing` between, so a burst cannot overrun the receiver's
/// socket buffer while a live contact still leaves within milliseconds.
/// The socket is `UDPSending` behind an injectable factory, so tests record
/// datagrams and nothing here touches the network.
@MainActor
@Observable
final class QSOBroadcaster {

    struct Config: Equatable, Sendable {
        var enabled: Bool
        var host: String
        var port: Int

        init(enabled: Bool = false, host: String = AppSettings.defaultQSOBroadcastHost,
             port: Int = AppSettings.defaultQSOBroadcastPort) {
            self.enabled = enabled
            self.host = host
            self.port = port
        }

        var destination: String { "\(host):\(port)" }
    }

    /// What the pane shows. UDP has no acknowledgement: `sent` is what left
    /// this Mac, never what RUMlogNG saved.
    enum Status: Equatable, Sendable {
        case off
        case ready(destination: String)
        case sent(count: Int, lastCall: String, at: Date, destination: String)
        case sending(done: Int, total: Int)
        case failed(String)

        var text: String {
            switch self {
            case .off:
                "Off — nothing is sent."
            case .ready(let destination):
                "Ready — \(destination). Nothing sent yet this session."
            case .sent(let count, let call, let at, let destination):
                "Sent \(call) at \(Self.clock.string(from: at))z to \(destination) · \(count) this session"
            case .sending(let done, let total):
                "Sending \(done.formatted()) of \(total.formatted())…"
            case .failed(let why):
                why
            }
        }

        var isFailure: Bool {
            if case .failed = self { return true }
            return false
        }

        private static let clock: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss"
            f.timeZone = TimeZone(identifier: "UTC")
            f.locale = Locale(identifier: "en_US_POSIX")
            return f
        }()
    }

    private(set) var config = Config()
    /// Datagrams sent since the window opened.
    private(set) var sentCount = 0
    private(set) var lastSentCall: String?
    private(set) var lastSentAt: Date?
    private(set) var lastFailure: String?
    private(set) var wholeLogDone = 0
    private(set) var wholeLogTotal: Int?

    var isSendingWholeLog: Bool { wholeLogTotal != nil }

    var status: Status {
        guard config.enabled else { return .off }
        if let total = wholeLogTotal { return .sending(done: wholeLogDone, total: total) }
        if let failure = lastFailure { return .failed(failure) }
        if let call = lastSentCall, let at = lastSentAt {
            return .sent(count: sentCount, lastCall: call, at: at, destination: config.destination)
        }
        return .ready(destination: config.destination)
    }

    /// The socket, opened on first use. A test hands in a recorder.
    @ObservationIgnored var makeSender: (String, UInt16) throws -> any UDPSending = { try UDPSender(host: $0, port: $1) }
    /// `StationName` — this Mac's name.
    @ObservationIgnored var stationName: String = Host.current().localizedName ?? "Mac"
    /// Between datagrams. 2,000 rows in ten seconds; zero in tests.
    @ObservationIgnored var pacing: Duration = .milliseconds(5)
    @ObservationIgnored var now: () -> Date = Date.init

    @ObservationIgnored private var sender: (any UDPSending)?
    @ObservationIgnored private var queue: [Queued] = []
    @ObservationIgnored private var drain: Task<Void, Never>?

    private struct Queued {
        let packet: N1MMContactBroadcast.Packet
        let wholeLog: Bool
    }

    private var station: N1MMContactBroadcast.Station { .init(stationName: stationName) }

    // MARK: Configuration

    /// The window pushes the preference on appear and on every change.
    /// Off closes the socket and drops the queue; a new host or port closes
    /// it, and the next packet reopens.
    func configure(_ new: Config) {
        guard new != config else { return }
        let destinationChanged = new.host != config.host || new.port != config.port
        config = new
        if !new.enabled || destinationChanged { closeSender() }
        if !new.enabled {
            queue.removeAll()
            drain?.cancel()
            drain = nil
            finishWholeLog()
        }
        lastFailure = nil
    }

    /// The window is closing.
    func shutdown() {
        queue.removeAll()
        drain?.cancel()
        drain = nil
        finishWholeLog()
        closeSender()
    }

    // MARK: Sending

    /// A document change. Nothing happens while off — the scoring closure,
    /// which reads the engine's fold, is never called.
    func handle(_ change: QSOChange, log: ContestLog, contest: ContestDefinition?,
                scoring: (QSO) -> N1MMContactBroadcast.RowScoring) {
        guard config.enabled else { return }
        guard let contest else {
            lastFailure = "No contest rules installed for \(log.partyID) — nothing sent."
            return
        }
        enqueue(N1MMContactBroadcast.packets(for: change, log: log, contest: contest, station: station, scoring: scoring),
                wholeLog: false)
    }

    /// Every row again, oldest first — the catch-up. A second call while one
    /// is running stops it (the button's *Stop*); live changes queued behind
    /// it still go.
    func sendWholeLog(log: ContestLog, contest: ContestDefinition?,
                      scoring: (QSO) -> N1MMContactBroadcast.RowScoring) {
        guard config.enabled else { return }
        if isSendingWholeLog {
            stopWholeLog()
            return
        }
        guard let contest else {
            lastFailure = "No contest rules installed for \(log.partyID) — nothing sent."
            return
        }
        let packets = N1MMContactBroadcast.wholeLog(log: log, contest: contest, station: station, scoring: scoring)
        guard !packets.isEmpty else { return }
        wholeLogTotal = packets.count
        wholeLogDone = 0
        lastFailure = nil
        enqueue(packets, wholeLog: true)
    }

    func stopWholeLog() {
        queue.removeAll { $0.wholeLog }
        finishWholeLog()
    }

    /// Waits for the queue to empty — for tests.
    func flush() async {
        while let task = drain { await task.value }
    }

    // MARK: The queue

    private func enqueue(_ packets: [N1MMContactBroadcast.Packet], wholeLog: Bool) {
        guard !packets.isEmpty else { return }
        queue.append(contentsOf: packets.map { Queued(packet: $0, wholeLog: wholeLog) })
        guard drain == nil else { return }
        drain = Task { [weak self] in
            await self?.drainQueue()
        }
    }

    private func drainQueue() async {
        while config.enabled, !queue.isEmpty, !Task.isCancelled {
            let next = queue.removeFirst()
            guard let sender = openSenderIfNeeded() else {
                // A destination that cannot be opened drops what was queued:
                // retrying every packet against a bad host is noise, and the
                // next change tries again once the field has been fixed.
                queue.removeAll()
                finishWholeLog()
                break
            }
            let failuresBefore = sender.sendFailures.count
            sender.send(next.packet.data)
            let failures = sender.sendFailures
            if failures.count > failuresBefore {
                let reason = failures.lastErrno.map { String(cString: strerror($0)) } ?? "unknown error"
                lastFailure = "Send failed: \(reason)"
            } else {
                lastFailure = nil
                sentCount += 1
                lastSentCall = next.packet.call
                lastSentAt = now()
            }
            if next.wholeLog {
                wholeLogDone += 1
                if let total = wholeLogTotal, wholeLogDone >= total { finishWholeLog() }
            }
            if pacing > .zero {
                try? await Task.sleep(for: pacing)
            } else {
                await Task.yield()
            }
        }
        // A cancelled drain leaves `drain` to whoever cancelled it: `configure`
        // has already cleared it, and may have started a successor.
        if !Task.isCancelled { drain = nil }
    }

    private func openSenderIfNeeded() -> (any UDPSending)? {
        if let sender { return sender }
        guard let port = UInt16(exactly: config.port), port > 0 else {
            lastFailure = "Port \(config.port) is not between 1 and 65535."
            return nil
        }
        do {
            let opened = try makeSender(config.host, port)
            sender = opened
            return opened
        } catch {
            lastFailure = error.localizedDescription
            return nil
        }
    }

    private func closeSender() {
        sender?.close()
        sender = nil
    }

    private func finishWholeLog() {
        wholeLogTotal = nil
        wholeLogDone = 0
    }
}

extension AppSettings {
    /// The three preferences as the broadcaster takes them, in one place so
    /// the pane and the window cannot drift over which key drives what.
    var qsoBroadcast: QSOBroadcaster.Config {
        QSOBroadcaster.Config(enabled: qsoBroadcastEnabled, host: qsoBroadcastHost, port: qsoBroadcastPort)
    }
}
```

- [ ] **Step 5.4: Run to verify it passes**

Run: `xcodegen generate && xcodebuild test … -only-testing:QSOPartyLoggerTests/QSOBroadcasterTests -only-testing:QSOPartyLoggerTests/QSOBroadcastPreferenceTests 2>&1 | tail -5`
Expected: both suites pass.

- [ ] **Step 5.5: Commit Tasks 4–5**

```bash
xcodegen generate
git add Sources/App/AppSettings.swift Sources/App/QSOBroadcaster.swift Tests/App/QSOBroadcasterTests.swift Tests/App/QSOBroadcastPreferenceTests.swift QSOPartyLogger.xcodeproj/project.pbxproj
git commit -m "app: QSOBroadcaster — the log's changes as paced N1MM datagrams to RUMlogNG, with its preferences"
```

---

### Task 6: ⇧⌘L

**Files:**
- Modify: `Sources/UI/KeyMonitorGate.swift` (`Action`, `commandAction`)
- Modify: `Sources/UI/KeyDiagnostics.swift` (`lastKeyReadout` switch, ~:195)
- Modify: `Sources/UI/ShortcutHint.swift` (`ShortcutLegend.items`)
- Test: `Tests/App/KeyMonitorGateTests.swift`, `Tests/App/ShortcutHintsTests.swift`

- [ ] **Step 6.1: Write the failing tests** — in `KeyMonitorGateTests` after `testShiftCommandBBoltsTheBandMap`:

```swift
    /// ⇧⌘L sends the whole log to RUMlogNG again (2026-09-07). ⌘L alone and
    /// a plain L stay with the field — 'L' is a letter in a callsign.
    func testShiftCommandLSendsTheLogToRUMlog() {
        XCTAssertEqual(KeyMonitorGate.action(keyCode: 37, command: true, shift: true), .sendLogToRUMlog)
        XCTAssertNil(KeyMonitorGate.action(keyCode: 37, command: true))
        XCTAssertNil(KeyMonitorGate.action(keyCode: 37, command: false))
        XCTAssertNil(KeyMonitorGate.action(keyCode: 37, command: false, shift: true))
        XCTAssertTrue(KeyMonitorGate.isShortcut(keyCode: 37, command: true, shift: true))
        let fromSheet = KeyMonitorGate.response(keyCode: 37, command: true, shift: true, focus: .sheet, repeatRunning: false)
        XCTAssertNil(fromSheet.action)
        XCTAssertFalse(fromSheet.consumesEvent)
    }
```

and in `ShortcutHintsTests.testLegendNamesEveryButtonlessKey` add `"⇧⌘L"` to the expected list.

- [ ] **Step 6.2: Run to verify it fails** — `-only-testing:QSOPartyLoggerTests/KeyMonitorGateTests -only-testing:QSOPartyLoggerTests/ShortcutHintsTests`. Expected: build error (`.sendLogToRUMlog`), legend assertion fails.

- [ ] **Step 6.3: Implement** — `KeyMonitorGate.Action`, after `toggleShortcutHints`:

```swift
        /// ⇧⌘L: every row of the log to RUMlogNG again, oldest first — the
        /// catch-up for a log made before sending was on (2026-09-07). A
        /// second press stops it.
        case sendLogToRUMlog
```

`commandAction`, after the `'e'` case:

```swift
        // ⇧⌘L — the whole log to RUMlogNG again. Only with ⇧: ⌘L alone is
        // left free, and a plain L is a letter in a callsign.
        case 37 where shift: return .sendLogToRUMlog  // 'l'
```

`KeyDiagnostics.lastKeyReadout` switch:

```swift
        case .sendLogToRUMlog: return "send the log to RUMlogNG"
```

`ShortcutLegend.items`, after the ⇧⌘B item:

```swift
        Item(keys: "⇧⌘L", action: "send the log to RUMlogNG"),
```

- [ ] **Step 6.4: Run to verify it passes.** The `perform` switch in `MainView` will not compile until Task 7 adds its case — do Task 7 Step 7.3 before running.

---

### Task 7: The pane, the toolbar button, the wiring

**Files:**
- Create: `Sources/UI/QSOBroadcastPane.swift`
- Modify: `Sources/UI/MainView.swift` — state (~:113), `.onChange` chain (~:538), toolbar (~:858), `onAppear` (~:1175), `onDisappear` (~:654), `perform` (~:2308)

- [ ] **Step 7.1: Create `Sources/UI/QSOBroadcastPane.swift`**

```swift
import SwiftUI

/// The RUMlog toolbar popover: send every QSO to RUMlogNG as it is logged
/// (N1MM's UDP contact packets), where to, what has left this Mac, and the
/// whole-log resend. Status is inline and never a modal; *sent* means the
/// datagram left, since UDP carries no reply.
struct QSOBroadcastPane: View {
    let broadcaster: QSOBroadcaster
    /// ⇧⌘L's action, so the button and the key do exactly the same thing.
    let sendWholeLog: () -> Void
    @State private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Send QSOs to RUMlogNG")
                .font(.headline)
            Text("Every contact you log, edit or delete goes to RUMlogNG the "
                 + "moment it happens, in the UDP packets N1MM Logger+ "
                 + "broadcasts — so the contest never needs importing.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Send QSOs as they are logged", isOn: $settings.qsoBroadcastEnabled)

            HStack(spacing: 6) {
                Text("Host")
                    .font(.callout)
                TextField(AppSettings.defaultQSOBroadcastHost, text: $settings.qsoBroadcastHost)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                Text("Port")
                    .font(.callout)
                TextField("Port", value: $settings.qsoBroadcastPort, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
            }

            Text(broadcaster.status.text)
                .font(.caption)
                .foregroundStyle(broadcaster.status.isFailure
                                 ? AnyShapeStyle(Color.orange)
                                 : AnyShapeStyle(.secondary))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                Button(broadcaster.isSendingWholeLog ? "Stop" : "Send Whole Log Now") {
                    sendWholeLog()
                }
                .disabled(!settings.qsoBroadcastEnabled)
                .shortcutHint("⇧⌘L")
                Text("Every row again, oldest first — for a log made before this "
                     + "was on, or a RUMlogNG that wasn't running.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("In RUMlogNG: Preferences › UDP › QSOs received from N1MM — "
                 + "Save QSO, port 12060. Sent means the packet left this Mac; "
                 + "UDP carries no reply, so RUMlogNG's log is the check. "
                 + "Another Mac's address works too — macOS asks for Local "
                 + "Network permission the first time.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 360)
    }
}
```

- [ ] **Step 7.2: Wire `MainView`**

State, after `showLookupPopover`:

```swift
    /// Every row change to RUMlogNG, as N1MM contact packets (2026-09-07).
    /// Wired to the document in `onAppear`; the toolbar popover configures it.
    @State private var broadcaster = QSOBroadcaster()
    @State private var showBroadcastPopover = false
```

`.onChange` chain, after `.onChange(of: settings.potaSpotsInParties)`:

```swift
        .onChange(of: settings.qsoBroadcast) { broadcaster.configure(settings.qsoBroadcast) }
```

Toolbar, after the Lookup button's `.popover`:

```swift
            Button {
                showBroadcastPopover.toggle()
            } label: {
                Label("RUMlog", systemImage: settings.qsoBroadcastEnabled ? "paperplane.fill" : "paperplane")
                    .foregroundStyle(broadcaster.status.isFailure ? .orange
                                     : settings.qsoBroadcastEnabled ? .green : .primary)
            }
            .help("Send every QSO to RUMlogNG as it is logged — N1MM's UDP packets. ⇧⌘L sends the whole log again")
            .shortcutHint("⇧⌘L")
            .popover(isPresented: $showBroadcastPopover) {
                QSOBroadcastPane(broadcaster: broadcaster, sendWholeLog: sendWholeLogToRUMlog)
            }
```

`onAppear`, after `syncPotaBoardClient()`:

```swift
        // Every row change to RUMlogNG. The scoring closure reads the fold
        // the window keeps for the table — the same generation, so no
        // second fold — and is never called while sending is off.
        broadcaster.configure(settings.qsoBroadcast)
        document.qsoObserver = { [weak broadcaster, weak document, weak liveScore] change in
            guard let broadcaster, let document else { return }
            broadcaster.handle(
                change, log: document.log,
                contest: ContestCatalog.contest(id: document.log.partyID),
                scoring: { Self.rowScoring($0, liveScore: liveScore) }
            )
        }
```

`onDisappear`, after `spotClient.disconnect()`:

```swift
        broadcaster.shutdown()
        document.qsoObserver = nil
```

`perform`:

```swift
        // ⇧⌘L: the whole log to RUMlogNG again; a second press stops it.
        case .sendLogToRUMlog: sendWholeLogToRUMlog()
```

and, near `syncHubSpotClient`:

```swift
    // MARK: RUMlogNG

    /// ⇧⌘L and the pane's button: every row again, oldest first.
    private func sendWholeLogToRUMlog() {
        broadcaster.sendWholeLog(
            log: document.log,
            contest: ContestCatalog.contest(id: document.log.partyID),
            scoring: { Self.rowScoring($0, liveScore: liveScore) }
        )
    }

    /// The engine's credit for a row, from the fold the window already
    /// keeps: `points` and `ismultiplier1` in the packet. Nothing when the
    /// log's rules are not installed.
    private static func rowScoring(_ row: QSO, liveScore: LiveScore?) -> N1MMContactBroadcast.RowScoring {
        guard let liveScore, liveScore.scoresWithRules else { return .none }
        let breakdown = liveScore.breakdown
        return .init(points: breakdown.pointsByRowID[row.id] ?? 0,
                     isNewMultiplier: breakdown.newMultRowIDs.contains(row.id))
    }
```

- [ ] **Step 7.3: Build, then run the UI-adjacent suites**

Run: `xcodegen generate && xcodebuild build -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger 2>&1 | grep -E "error|warning: unused|BUILD" | head`
Expected: `** BUILD SUCCEEDED **`, no errors.
Run: `xcodebuild test … -only-testing:QSOPartyLoggerTests/KeyMonitorGateTests -only-testing:QSOPartyLoggerTests/ShortcutHintsTests -only-testing:QSOPartyLoggerTests/WindowSizeTests 2>&1 | tail -3`
Expected: `** TEST SUCCEEDED **` (WindowSizeTests pins the window's minimum, which a wider toolbar could move).

---

### Task 8: Documentation, the full run, the commit

**Files:**
- Modify: `README.md` (Quick start, keyboard table, Files and export, test count), `docs/PROVENANCE.md`, `project.yml`, `Resources/Info.plist`

- [ ] **Step 8.1: README** — Quick start, a step 6:

```markdown
6. Optional: the **RUMlog** toolbar button sends every QSO to RUMlogNG as you
   log it, so the contest never needs importing.
```

Keyboard table, after the `⌘E / ⇧⌘E` rows:

```markdown
| `⇧⌘L` | Send the whole log to RUMlogNG again — every row, oldest first, paced (the RUMlog toolbar popover turns the live feed on and says what has left this Mac); pressing it while a send runs stops it |
```

A new subsection at the end of *Files and export*, before *POTA activations on any contest*:

```markdown
### Sending QSOs to RUMlogNG

If your station log lives in RUMlogNG, the contest never needs importing.
The **RUMlog** toolbar button opens a small pane: turn on **Send QSOs as
they are logged** and every contact goes to RUMlogNG the moment you press
Return, in the same UDP packets N1MM Logger+ broadcasts — which is what
RUMlogNG's *QSOs received from N1MM* listener saves. Edits and deletions
follow (an edit is N1MM's own delete-then-replace pair, so RUMlogNG's copy
tracks corrections, not just additions), and so does ⌘Z. County-line
contacts arrive as one QSO per county, exactly as they sit in the log and in
the ADIF.

On RUMlogNG's side: Preferences › UDP › **QSOs received from N1MM** → *Save
QSO*, port 12060. The pane's defaults — `127.0.0.1`, `12060` — reach a
RUMlogNG on this Mac; put another Mac's address (or `192.168.1.255` for the
whole subnet) in the Host field to reach one elsewhere, and allow the Local
Network prompt macOS raises the first time.

**⇧⌘L — Send Whole Log Now** resends every row, oldest first, paced so a
two-thousand-QSO log takes about ten seconds and drops nothing. That is the
catch-up for a log made before the feature was on, a RUMlogNG that was not
running, or a doubt — a QSO RUMlogNG already has is a duplicate by its own
rules. Press it again to stop.

The pane's status line says what left this Mac — *Sent W0BH at 14:32:05z to
127.0.0.1:12060 · 12 this session* — and turns orange, in the kernel's own
words, when a packet could not be sent or the host could not be resolved.
UDP carries no reply, so *sent* never means *saved*; RUMlogNG's log is the
check.

What goes out is N1MM's `contactinfo` packet field for field, from N1MM's
own documentation (banked in
[`docs/research/n1mm-udp-contactinfo.md`](docs/research/n1mm-udp-contactinfo.md)):
the contest's Cabrillo name, the time in UTC, band, frequency in 10 Hz
units, mode (`SSB` as the band's sideband, since N1MM's vocabulary is
`USB`/`LSB`), reports, serials, the received exchange, section, zone,
precedence, check, the engine's points and new-multiplier flag, Run or S&P,
and a stable ID per row — plus the `dxcc` and `my_gridsquare` elements
RUMlogNG's own broadcast carries. Anything else on the LAN that reads
N1MM's packets (Log4OM, DXKeeper's gateway, MacLoggerDX…) hears the same
feed.
```

- [ ] **Step 8.2: `docs/PROVENANCE.md`** — after the *Super check partial* bullet:

```markdown
- Sending QSOs to RUMlogNG: every element of the N1MM `contactinfo`,
  `contactreplace` and `contactdelete` packets, their order, the 10 Hz
  frequency unit, the band token, the 32-hex-character ID and the
  delete-then-replace edit sequence come from the N1MM Logger+ **"External
  UDP Messages"** page (n1mmwp.hamdocs.com/appendices/external-udp-broadcasts/,
  fetched 2026-09-07); what RUMlogNG's *QSOs received from N1MM* listener
  is comes from RUMlogNG's own documentation, version history (5.0: "Real
  time import from other loggers in N1MM format") and its author's forum
  packet (dl2rum.de, fetched 2026-09-07), which also supplies the two
  trailing elements RUMlogNG itself sends (`dxcc`, `my_gridsquare`). Banked
  with quotes in
  [`docs/research/n1mm-udp-contactinfo.md`](research/n1mm-udp-contactinfo.md).
  Two spellings on N1MM's page (`exchangel`, `ismultiplierl`) are emitted
  with the digit, on the evidence recorded there. No other logger's code
  was read for a byte.
```

- [ ] **Step 8.3: Local Network string** — `project.yml` and `Resources/Info.plist`:

`QSO Party Logger connects to your FlexRadio and DX cluster spotting nodes on your local network, and sends your QSOs to RUMlogNG when you ask it to.`

- [ ] **Step 8.4: The full run** — first `pgrep -fl QSOPartyLogger` must print nothing.

Run: `xcodegen generate && set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' 2>&1 | tee /tmp/claude-scratch/full-run.log | grep -E "Executed [0-9]+ tests|error:|failed|TEST (SUCCEEDED|FAILED)" | tail -8`
Expected: `Executed N tests, with 0 failures` and `** TEST SUCCEEDED **`. If `CWKeyerTests.testOnFinishedFiresAfterAbort` alone fails, rerun that suite by itself (known flake under load).

- [ ] **Step 8.5: Test count** — put `N` from the run into README's `**N unit tests**` line, and add to its list "the N1MM contact packets byte for byte and the paced RUMlogNG sender".

- [ ] **Step 8.6: Commit**

```bash
xcodegen generate
git add Sources/UI/KeyMonitorGate.swift Sources/UI/KeyDiagnostics.swift Sources/UI/ShortcutHint.swift Sources/UI/QSOBroadcastPane.swift Sources/UI/MainView.swift Tests/App/KeyMonitorGateTests.swift Tests/App/ShortcutHintsTests.swift README.md docs/PROVENANCE.md project.yml Resources/Info.plist QSOPartyLogger.xcodeproj/project.pbxproj
git commit -m "ui: the RUMlog pane — every QSO to RUMlogNG as it is logged, ⇧⌘L for the whole log"
```

---

## Self-review

- **Spec coverage:** §2 pane → Task 7; §3.1 seam → Task 1; §3.2 packets and every table row → Task 2 (`dxcc`/`my_gridsquare` included; `my_gridsquare` always present, empty when unset); §3.3 queue, pacing, status, failures → Task 5; §3.4 wiring, ⇧⌘L, legend, diagnostics → Tasks 6–7; §3.5 preferences → Task 4; §6 tests → each task; §7 docs → Task 8; `SO_BROADCAST` → Task 3.
- **Placeholders:** none.
- **Type consistency:** `QSOChange.Replacement(old:new:)`; `N1MMContactBroadcast.{Station, RowScoring, Packet, contactInfo, contactReplace(row:replacing:), contactDelete, packets(for:), wholeLog, bandToken, frequencyTens, mode, timestamp, id, escape}`; `QSOBroadcaster.{Config, Status, configure, handle, sendWholeLog, stopWholeLog, shutdown, flush, makeSender, stationName, pacing, now, isSendingWholeLog, status}`; `AppSettings.{qsoBroadcastEnabled, qsoBroadcastHost, qsoBroadcastPort, defaultQSOBroadcastHost, defaultQSOBroadcastPort, qsoBroadcast}`; `KeyMonitorGate.Action.sendLogToRUMlog` — used identically across tasks.
