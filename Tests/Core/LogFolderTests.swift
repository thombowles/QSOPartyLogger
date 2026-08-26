import XCTest
@testable import QSOPartyLogger

/// The contest history is the `.qplog` files in the logs folder, read one
/// level deep: each set-up log with QSOs is one record, stamped by its
/// file's modification date, scored by the snapshot it carries or, failing
/// that, by the rules installed now.
final class LogFolderTests: XCTestCase {

    private var folder: URL!
    private let t0 = Date(timeIntervalSince1970: 1_770_000_000)  // 2026-02-02

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("LogFolderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func qso(_ call: String, their: String = "MO", offset: TimeInterval = 0) -> QSO {
        QSO(
            timestampUTC: t0.addingTimeInterval(offset),
            call: call,
            band: .m20,
            modeClass: .cw,
            rawMode: "CW",
            rstSent: "599",
            rstRcvd: "599",
            myLoc: "SED",
            theirLoc: their
        )
    }

    private func log(
        partyID: String = "ksqp",
        callsign: String = "KE5CW",
        qsos: [QSO],
        completed: Bool = true
    ) -> ContestLog {
        var log = ContestLog(partyID: partyID)
        log.station.callsign = callsign
        log.myLocation = .inState(counties: ["SED"])
        log.qsos = qsos
        log.setupCompleted = completed
        return log
    }

    @discardableResult
    private func write(_ log: ContestLog, as name: String, modified: Date? = nil, in dir: URL? = nil) throws -> URL {
        let url = (dir ?? folder).appendingPathComponent(name)
        try log.encoded().write(to: url, options: .atomic)
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path(percentEncoded: false))
        }
        return url
    }

    private var ksqp: ContestRecord.Identity {
        ContestRecord.Identity(partyID: "ksqp", year: 2026, callsign: "KE5CW")
    }

    // MARK: Records from files

    func testEachSetUpLogWithQSOsIsOneRecord() throws {
        try write(log(qsos: [qso("W0AAA"), qso("K5BBB", offset: 60)]), as: "2026-08-29 KSQP KE5CW.qplog", modified: t0)
        try write(log(partyID: "tqp", qsos: [qso("N5XYZ", their: "HARR")]), as: "2026-09-19 TQP KE5CW.qplog", modified: t0.addingTimeInterval(60))

        let history = try LogFolder(url: folder).history()
        XCTAssertEqual(history.archive.records.count, 2)
        let ksqp = try XCTUnwrap(history.archive.records.first { $0.partyID == "ksqp" })
        XCTAssertEqual(ksqp.identity, self.ksqp)
        XCTAssertEqual(ksqp.qsos.count, 2)
        XCTAssertEqual(ksqp.sourceFileName, "2026-08-29 KSQP KE5CW.qplog")
        XCTAssertEqual(ksqp.updatedAt, t0)                       // the file's own date
        XCTAssertEqual(history.duplicates, [])
        XCTAssertEqual(history.unreadable, [])
        XCTAssertEqual(history.downloading, 0)
    }

    func testDraftsAreSkipped() throws {
        try write(log(qsos: [qso("W0AAA")], completed: false), as: "not set up.qplog")
        try write(log(qsos: []), as: "empty.qplog")
        try write(log(callsign: "", qsos: [qso("W0AAA")]), as: "no call.qplog")
        let history = try LogFolder(url: folder).history()
        XCTAssertEqual(history.archive, .empty)
        XCTAssertEqual(history.unreadable, [])
    }

    /// Only `.qplog` files, and only this folder: a log dragged into a
    /// subfolder is kept without counting; the RumLog exports beside the
    /// folder are not ours.
    func testOtherFilesAndSubfoldersAreIgnored() throws {
        try Data("<adif>".utf8).write(to: folder.appendingPathComponent("KE5CW.adi"))
        try Data("{}".utf8).write(to: folder.appendingPathComponent("Contest History.qphistory"))
        let practice = folder.appendingPathComponent("Practice", isDirectory: true)
        try FileManager.default.createDirectory(at: practice, withIntermediateDirectories: true)
        try write(log(qsos: [qso("W0AAA")]), as: "practice run.qplog", in: practice)

        let history = try LogFolder(url: folder).history()
        XCTAssertEqual(history.archive, .empty)
        XCTAssertEqual(history.unreadable, [])
    }

    func testMissingFolderIsEmptyNotAnError() throws {
        let gone = folder.appendingPathComponent("nope", isDirectory: true)
        let history = try LogFolder(url: gone).history()
        XCTAssertEqual(history, .empty)
    }

    // MARK: Which score

    /// A snapshot saved with the log is the frozen "what I claimed" figure —
    /// used verbatim even when the log would score differently today.
    func testSavedSnapshotWithFiguresIsUsedVerbatim() throws {
        let party = try XCTUnwrap(PartyCatalog.party(id: "ksqp"))
        var saved = log(qsos: [qso("W0AAA", their: party.counties[0].abbr)])
        var frozen = try XCTUnwrap(saved.stampingScoreSnapshot().scoreSnapshot)
        frozen.figures?.total = 123_456          // "last season's rules said so"
        saved.scoreSnapshot = frozen
        try write(saved, as: "a.qplog")

        let record = try XCTUnwrap(try LogFolder(url: folder).history().archive.records.first)
        XCTAssertEqual(record.snapshot, frozen)
        XCTAssertEqual(record.snapshot.figures?.total, 123_456)
        XCTAssertEqual(record.scoreOrigin, .savedWithLog)
    }

    /// A log saved by a build before snapshots existed is scored now, with
    /// the rules installed here, and says so.
    func testLogWithoutASnapshotIsScoredNow() throws {
        let party = try XCTUnwrap(PartyCatalog.party(id: "ksqp"))
        try write(log(qsos: [qso("W0AAA", their: party.counties[0].abbr)]), as: "old build.qplog")

        let record = try XCTUnwrap(try LogFolder(url: folder).history().archive.records.first)
        XCTAssertEqual(record.snapshot.validQSOs, 1)
        XCTAssertGreaterThan(try XCTUnwrap(record.snapshot.figures).total, 0)
        XCTAssertEqual(record.scoreOrigin, .computedNow)
    }

    /// Saved on a Mac without the party's rules (counts only), read on one
    /// that has them: the better score is computed now.
    func testCountsOnlySnapshotIsRescoredWhenThePartyIsInstalledHere() throws {
        let party = try XCTUnwrap(PartyCatalog.party(id: "ksqp"))
        var saved = log(qsos: [qso("W0AAA", their: party.counties[0].abbr)])
        saved.scoreSnapshot = ScoreSnapshot.countsOnly(log: saved)
        try write(saved, as: "a.qplog")

        let record = try XCTUnwrap(try LogFolder(url: folder).history().archive.records.first)
        XCTAssertNotNil(record.snapshot.figures)
        XCTAssertEqual(record.scoreOrigin, .computedNow)
    }

    func testUnknownPartyWithoutASnapshotIsCountsOnly() throws {
        try write(log(partyID: "no-such-party", qsos: [qso("W0AAA")]), as: "a.qplog")
        let record = try XCTUnwrap(try LogFolder(url: folder).history().archive.records.first)
        XCTAssertEqual(record.snapshot.validQSOs, 1)
        XCTAssertNil(record.snapshot.figures)
    }

    // MARK: Duplicates, corrupt files, placeholders

    /// Two files for one contest — a copy, an iCloud "2" duplicate: the
    /// later-modified one is shown and the other is named.
    func testDuplicateLogsFoldToTheLaterModifiedAndAreNamed() throws {
        try write(log(qsos: [qso("W0AAA")]), as: "2026-08-29 KSQP KE5CW.qplog", modified: t0)
        try write(log(qsos: [qso("W0AAA"), qso("K5BBB", offset: 60)]), as: "2026-08-29 KSQP KE5CW 2.qplog", modified: t0.addingTimeInterval(60))

        let history = try LogFolder(url: folder).history()
        XCTAssertEqual(history.archive.records.count, 1)
        XCTAssertEqual(history.archive.records[0].qsos.count, 2)
        XCTAssertEqual(history.archive.records[0].sourceFileName, "2026-08-29 KSQP KE5CW 2.qplog")
        XCTAssertEqual(history.duplicates, [
            LogFolder.Duplicate(identity: ksqp, shown: "2026-08-29 KSQP KE5CW 2.qplog", others: ["2026-08-29 KSQP KE5CW.qplog"])
        ])
    }

    /// One bad file is named and skipped — never hides the rest, never
    /// touched.
    func testCorruptFileIsNamedNotFatal() throws {
        try write(log(qsos: [qso("W0AAA")]), as: "good.qplog")
        let bad = folder.appendingPathComponent("bad.qplog")
        try Data("not json {{{".utf8).write(to: bad)

        let history = try LogFolder(url: folder).history()
        XCTAssertEqual(history.archive.records.count, 1)
        XCTAssertEqual(history.unreadable, ["bad.qplog"])
        XCTAssertEqual(try Data(contentsOf: bad), Data("not json {{{".utf8))
    }

    /// `.<name>.qplog.icloud` is iCloud's stand-in for a log not downloaded
    /// here — counted, so an incomplete season doesn't read as a small one.
    func testPlaceholdersAreCounted() throws {
        try Data().write(to: folder.appendingPathComponent(".2026-08-29 KSQP KE5CW.qplog.icloud"))
        let history = try LogFolder(url: folder).history()
        XCTAssertEqual(history.downloading, 1)
        XCTAssertEqual(history.archive, .empty)
        XCTAssertEqual(history.unreadable, [])
    }

    // MARK: POTA — a program log is an outing, not an annual entry

    private func potaQSO(
        _ call: String, park: String? = nil, offset: TimeInterval = 0
    ) -> QSO {
        QSO(
            timestampUTC: t0.addingTimeInterval(offset),
            call: call,
            band: .m20,
            modeClass: .cw,
            rawMode: "CW",
            rstSent: "599",
            rstRcvd: "599",
            myPotaRefs: park.map { [$0] },
            myLoc: "",
            theirLoc: ""
        )
    }

    private func potaLog(qsos: [QSO]) -> ContestLog {
        var log = ContestLog(partyID: "pota")
        log.station.callsign = "KE5CW"
        log.myLocation = .outOfState(location: "MO")
        log.qsos = qsos
        log.setupCompleted = true
        return log
    }

    /// Every activation of a year is its own record — partyID|year|callsign
    /// would fold a season of POTA into one row behind a bogus "two files
    /// for one contest" warning.
    func testEachPotaOutingIsItsOwnRecord() throws {
        try write(potaLog(qsos: [potaQSO("W0AAA", park: "US-1234")]),
                  as: "2026-02-02-KE5CW@US-1234.qplog", modified: t0)
        try write(potaLog(qsos: [potaQSO("W0BBB", park: "US-5678", offset: 86_400)]),
                  as: "2026-02-03-KE5CW@US-5678.qplog", modified: t0.addingTimeInterval(60))

        let history = try LogFolder(url: folder).history()
        XCTAssertEqual(history.archive.records.count, 2)
        XCTAssertEqual(history.duplicates, [])
        XCTAssertEqual(Set(history.archive.records.map(\.id)).count, 2)
    }

    /// A rover's two same-day files at two parks are two outings.
    func testSameDayDifferentParksAreDistinctOutings() throws {
        try write(potaLog(qsos: [potaQSO("W0AAA", park: "US-1234")]),
                  as: "2026-02-02-KE5CW@US-1234.qplog", modified: t0)
        try write(potaLog(qsos: [potaQSO("W0AAA", park: "US-5678", offset: 3_600)]),
                  as: "2026-02-02-KE5CW@US-5678.qplog", modified: t0)

        let history = try LogFolder(url: folder).history()
        XCTAssertEqual(history.archive.records.count, 2)
        XCTAssertEqual(history.duplicates, [])
    }

    /// An iCloud "2" copy is the same outing — same UTC day, same parks —
    /// and still folds to the later-modified file, named.
    func testICloudCopyOfAnOutingStillFolds() throws {
        try write(potaLog(qsos: [potaQSO("W0AAA", park: "US-1234")]),
                  as: "2026-02-02-KE5CW@US-1234.qplog", modified: t0)
        try write(potaLog(qsos: [potaQSO("W0AAA", park: "US-1234"), potaQSO("K5BBB", park: "US-1234", offset: 60)]),
                  as: "2026-02-02-KE5CW@US-1234 2.qplog", modified: t0.addingTimeInterval(60))

        let history = try LogFolder(url: folder).history()
        XCTAssertEqual(history.archive.records.count, 1)
        XCTAssertEqual(history.archive.records[0].sourceFileName, "2026-02-02-KE5CW@US-1234 2.qplog")
        XCTAssertEqual(history.duplicates.count, 1)
        XCTAssertEqual(history.duplicates.first?.others, ["2026-02-02-KE5CW@US-1234.qplog"])
    }

    /// A hunter log has no park — its outing is the UTC day alone.
    func testHunterOutingsAreDistinctByDay() throws {
        try write(potaLog(qsos: [potaQSO("W0AAA")]), as: "hunting day one.qplog", modified: t0)
        try write(potaLog(qsos: [potaQSO("W0BBB", offset: 86_400)]), as: "hunting day two.qplog", modified: t0)

        let history = try LogFolder(url: folder).history()
        XCTAssertEqual(history.archive.records.count, 2)
        XCTAssertEqual(history.duplicates, [])
    }

    /// The outing itself: UTC day of the first QSO plus the sorted parks
    /// worked from, straight from the rows (the log's current-park set can
    /// lag a rover). Parties stay outing-free — identity and id unchanged.
    func testOutingNamesTheDayAndParks() throws {
        try write(potaLog(qsos: [
            potaQSO("W0AAA", park: "US-5678"),
            potaQSO("W0BBB", park: "US-1234", offset: 60),
        ]), as: "rove.qplog", modified: t0)
        try write(log(qsos: [qso("W0AAA")]), as: "2026-08-29 KSQP KE5CW.qplog", modified: t0)

        let history = try LogFolder(url: folder).history()
        let pota = try XCTUnwrap(history.archive.records.first { $0.partyID == "pota" })
        XCTAssertEqual(pota.outing, "20260202@US-1234+US-5678")
        XCTAssertEqual(pota.id, "pota|2026|KE5CW|20260202@US-1234+US-5678")
        XCTAssertEqual(pota.identity,
                       ContestRecord.Identity(partyID: "pota", year: 2026, callsign: "KE5CW",
                                              outing: "20260202@US-1234+US-5678"))

        let ksqp = try XCTUnwrap(history.archive.records.first { $0.partyID == "ksqp" })
        XCTAssertNil(ksqp.outing)
        XCTAssertEqual(ksqp.id, "ksqp|2026|KE5CW")
        XCTAssertEqual(ksqp.identity, self.ksqp)
    }
}
