import XCTest
@testable import QSOPartyLogger

final class LogDocumentTests: XCTestCase {

    /// Regression: `DocumentGroup`'s new-document factory runs on a background
    /// dispatch queue. `LogDocument()` must be constructible off the main
    /// thread — an earlier version wrapped it in `MainActor.assumeIsolated`,
    /// which tripped a dispatch assertion and crashed on launch.
    func testConstructsOffMainThread() {
        let done = expectation(description: "constructed off main")
        DispatchQueue.global(qos: .userInitiated).async {
            XCTAssertFalse(Thread.isMainThread, "must exercise the background path")
            let document = LogDocument()
            XCTAssertEqual(document.log.partyID, "ksqp")
            XCTAssertEqual(document.log.qsos.count, 0)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }

    func testSavedStationProfileReadIsThreadSafe() {
        // Reading the persisted profile must not require the main actor.
        let done = expectation(description: "read off main")
        DispatchQueue.global().async {
            _ = LogDocument.savedStationProfile()  // may be nil; must not crash
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }

    // MARK: Message defaults follow the party (2026-07-25)

    /// A new document starts at ksqp and the operator picks the real party in
    /// Contest Setup, so the macros have to follow that choice — deriving them
    /// at init alone would give a CQP operator Kansas's macros.
    @MainActor
    func testUntouchedMacrosFollowThePartyChosenInSetup() throws {
        let doc = LogDocument()
        XCTAssertEqual(doc.log.partyID, "ksqp")
        XCTAssertEqual(doc.log.messages, MessageSets.standard, "precondition")

        doc.updateStation(
            StationProfile(), location: .outOfState(location: "TX"),
            partyID: "cqp", undoManager: nil
        )
        XCTAssertEqual(doc.log.messages.run[1], "{CALL} {SERIAL} {EXCH}")
        XCTAssertEqual(
            doc.log.messages,
            MessageSets.defaults(for: PartyCatalog.party(id: "cqp"))
        )
    }

    @MainActor
    func testCustomisedMacrosSurviveAPartyChange() throws {
        let doc = LogDocument()
        var custom = MessageSets.standard
        custom.run[0] = "CQ CQP {MYCALL} {MYCALL}"
        doc.log.messages = custom

        doc.updateStation(
            StationProfile(), location: .outOfState(location: "TX"),
            partyID: "cqp", undoManager: nil
        )
        XCTAssertEqual(doc.log.messages, custom,
                       "an edited set encodes an on-air habit; it is not ours to rewrite")
    }

    /// Undo must be an exact inverse: a Kansas log must not keep California
    /// macros after the party change is undone.
    @MainActor
    func testUndoRestoresBothPartyAndMacros() throws {
        let doc = LogDocument()
        let undo = UndoManager()
        doc.updateStation(
            StationProfile(), location: .outOfState(location: "TX"),
            partyID: "cqp", undoManager: undo
        )
        XCTAssertEqual(doc.log.messages.run[1], "{CALL} {SERIAL} {EXCH}", "precondition")

        undo.undo()
        XCTAssertEqual(doc.log.partyID, "ksqp")
        XCTAssertEqual(doc.log.messages, MessageSets.standard)
    }

    /// The open path: a CQP log saved before this change carries the old fixed
    /// report macros, and gets upgraded.
    func testOpeningACQPLogUpgradesUntouchedMacros() {
        var saved = ContestLog(partyID: "cqp")
        saved.messages = MessageSets.standard
        let opened = LogDocument.upgradingUntouchedMessages(saved)
        XCTAssertEqual(opened.messages.run[1], "{CALL} {SERIAL} {EXCH}")
    }

    func testOpeningACQPLogLeavesEditedMacrosAlone() {
        var saved = ContestLog(partyID: "cqp")
        var custom = MessageSets.standard
        custom.run[1] = "{CALL} 5NN {EXCH} HI HI"
        saved.messages = custom
        XCTAssertEqual(LogDocument.upgradingUntouchedMessages(saved).messages, custom)
    }

    func testOpeningAReportPartyLogChangesNothing() {
        var saved = ContestLog(partyID: "ksqp")
        saved.messages = MessageSets.standard
        XCTAssertEqual(
            LogDocument.upgradingUntouchedMessages(saved).messages, MessageSets.standard
        )
    }

    /// Re-opening an already-upgraded log is a no-op, not a second rewrite.
    func testOpeningAnAlreadyUpgradedLogIsIdempotent() {
        var saved = ContestLog(partyID: "cqp")
        saved.messages = MessageSets.defaults(for: PartyCatalog.party(id: "cqp"))
        let once = LogDocument.upgradingUntouchedMessages(saved)
        XCTAssertEqual(once.messages, saved.messages)
        XCTAssertEqual(LogDocument.upgradingUntouchedMessages(once).messages, saved.messages)
    }

    /// Two party changes without an intervening report party. After the first
    /// hop the stored set is untouched *for CQP* but is no longer `.standard`,
    /// so only the `defaults(for: oldParty)` baseline still recognises it as
    /// unedited. Comparing against `.standard` here would strand a CQP
    /// operator's macros on a Kansas log.
    @MainActor
    func testUntouchedMacrosFollowAHopBetweenPartiesOfDifferentShape() throws {
        let doc = LogDocument()
        doc.updateStation(
            StationProfile(), location: .outOfState(location: "TX"),
            partyID: "cqp", undoManager: nil
        )
        XCTAssertEqual(
            doc.log.messages, MessageSets.defaults(for: PartyCatalog.party(id: "cqp")),
            "precondition: untouched, in CQP's shape, and no longer .standard"
        )

        doc.updateStation(
            StationProfile(), location: .outOfState(location: "TX"),
            partyID: "ksqp", undoManager: nil
        )
        XCTAssertEqual(doc.log.messages.run[1], "{CALL} {RST} {EXCH}")
        XCTAssertEqual(doc.log.messages, MessageSets.standard,
                       "a report party's macros must come back")
    }

    /// Undo's statement order is load-bearing: the nested `updateStation` may
    /// re-derive, and the explicit restore afterwards is what makes undo exact.
    /// Observable only here — macros that are customised relative to KSQP yet
    /// identical to what CQP derives, so the nested call re-derives on the way
    /// back and the restore has to overrule it.
    @MainActor
    func testUndoIsExactEvenWhenTheNestedCallWouldReDerive() throws {
        let doc = LogDocument()
        let serialForm = MessageSets.defaults(for: PartyCatalog.party(id: "cqp"))
        doc.log.messages = serialForm

        let undo = UndoManager()
        doc.updateStation(
            StationProfile(), location: .outOfState(location: "TX"),
            partyID: "cqp", undoManager: undo
        )
        XCTAssertEqual(doc.log.messages, serialForm,
                       "customised relative to KSQP, so left alone")

        undo.undo()
        XCTAssertEqual(doc.log.partyID, "ksqp")
        XCTAssertEqual(doc.log.messages, serialForm,
                       "restored exactly, not replaced by what KSQP would derive")
    }

    /// Pins the wiring itself, not just the transform: deleting the upgrade
    /// call from the open path previously left the whole suite green.
    func testDecodeUpgradingRoutesThroughTheUpgrade() throws {
        var saved = ContestLog(partyID: "cqp")
        saved.messages = MessageSets.standard
        let opened = try LogDocument.decodeUpgrading(saved.encoded())
        XCTAssertEqual(opened.messages,
                       MessageSets.defaults(for: PartyCatalog.party(id: "cqp")))
    }

    /// The oldest real file on disk: written before per-contest macros existed,
    /// so it carries no `messages` key at all. It decodes to `.standard` and
    /// must then be upgraded — the full decode-then-upgrade chain, which no
    /// test previously exercised. The fixture is derived from the model rather
    /// than hand-typed, so it cannot drift from `StationProfile`.
    func testOpeningALogPredatingPerContestMacrosUpgradesIt() throws {
        let log = ContestLog(partyID: "cqp")
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: log.encoded()) as? [String: Any]
        )
        XCTAssertNotNil(object.removeValue(forKey: "messages"),
                        "the key must exist before removing it, or this proves nothing")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let opened = try LogDocument.decodeUpgrading(legacy)
        XCTAssertEqual(opened.messages.run[1], "{CALL} {SERIAL} {EXCH}",
                       "absent messages key decodes to .standard, then upgrades")
    }

    /// `init()` pairs a literal party id with `ContestLog`'s literal `.standard`
    /// macros. That is correct only while the new-document party derives exactly
    /// `.standard`; if it ever becomes a party that sends a QSO number, the
    /// macros would be wrong *and* would then read as customised and never be
    /// fixed.
    func testNewDocumentsMacrosMatchItsParty() {
        let doc = LogDocument()
        XCTAssertEqual(
            doc.log.messages,
            MessageSets.defaults(for: PartyCatalog.party(id: doc.log.partyID)),
            "new-document party and its default macros must agree"
        )
    }

    // MARK: Operating mode re-derivation (2026-07-25)

    @MainActor
    func testSetupPicksTheModeForAnOutOfStateOperator() throws {
        let doc = LogDocument()
        doc.updateStation(
            StationProfile(), location: .outOfState(location: "TX"),
            partyID: "ksqp", undoManager: nil
        )
        XCTAssertEqual(doc.log.operatingMode, .searchPounce)
    }

    @MainActor
    func testSetupPicksTheModeForAnInStateOperator() throws {
        let doc = LogDocument()
        doc.updateStation(
            StationProfile(), location: .inState(counties: ["SED"]),
            partyID: "ksqp", undoManager: nil
        )
        XCTAssertEqual(doc.log.operatingMode, .run)
    }

    /// Reopening Contest Setup to fix a callsign typo must not undo a
    /// deliberate mid-contest switch to Run.
    @MainActor
    func testAnEditOnTheSameSideOfTheLineKeepsADeliberateSwitch() throws {
        let doc = LogDocument()
        doc.updateStation(
            StationProfile(), location: .outOfState(location: "TX"),
            partyID: "ksqp", undoManager: nil
        )
        doc.log.operatingMode = .run  // the operator switches by hand

        var fixed = StationProfile()
        fixed.callsign = "KE5CW"
        doc.updateStation(
            fixed, location: .outOfState(location: "TX"),
            partyID: "ksqp", undoManager: nil
        )
        XCTAssertEqual(doc.log.operatingMode, .run, "still out of state — nothing flipped")

        // Still out of state, different state: also not a flip.
        doc.updateStation(
            fixed, location: .outOfState(location: "OK"),
            partyID: "ksqp", undoManager: nil
        )
        XCTAssertEqual(doc.log.operatingMode, .run)
    }

    /// Crossing the state line is the one location change that implies a
    /// different operating style.
    @MainActor
    func testCrossingTheStateLineReDerivesTheMode() throws {
        let doc = LogDocument()
        doc.updateStation(
            StationProfile(), location: .outOfState(location: "TX"),
            partyID: "ksqp", undoManager: nil
        )
        XCTAssertEqual(doc.log.operatingMode, .searchPounce, "precondition")

        doc.updateStation(
            StationProfile(), location: .inState(counties: ["SED"]),
            partyID: "ksqp", undoManager: nil
        )
        XCTAssertEqual(doc.log.operatingMode, .run)
    }

    /// A county change within the state is not a flip.
    @MainActor
    func testChangingCountyWithinTheStateKeepsTheMode() throws {
        let doc = LogDocument()
        doc.updateStation(
            StationProfile(), location: .inState(counties: ["SED"]),
            partyID: "ksqp", undoManager: nil
        )
        doc.log.operatingMode = .searchPounce  // deliberate

        doc.updateStation(
            StationProfile(), location: .inState(counties: ["BUT"]),
            partyID: "ksqp", undoManager: nil
        )
        XCTAssertEqual(doc.log.operatingMode, .searchPounce)
    }

    /// Undo restores the mode the operator actually had, not what the old
    /// location would derive. An out-of-state operator who switched to Run by
    /// hand and then crossed the line must get Run back on undo — re-deriving
    /// would silently discard a deliberate choice they never see reverted.
    @MainActor
    func testUndoRestoresAManuallyChosenModeAcrossAFlip() throws {
        let doc = LogDocument()
        doc.updateStation(
            StationProfile(), location: .outOfState(location: "TX"),
            partyID: "ksqp", undoManager: nil
        )
        doc.log.operatingMode = .run  // by hand, and deliberately not undoable

        let undo = UndoManager()
        doc.updateStation(
            StationProfile(), location: .inState(counties: ["SED"]),
            partyID: "ksqp", undoManager: undo
        )

        undo.undo()
        XCTAssertFalse(doc.log.myLocation.isInState, "precondition: back out of state")
        XCTAssertEqual(doc.log.operatingMode, .run,
                       "the manual choice survives; re-deriving would give S&P")
    }

    // MARK: Export file naming (2026-07-28)

    /// The export panel offers the log's own name, not the bare callsign: a
    /// saved document exports under its file name...
    func testExportBaseNameUsesTheSavedFilesName() {
        let url = URL(fileURLWithPath: "/logs/2026-08-29 KSQP KE5CW.qplog")
        XCTAssertEqual(
            LogDocument.exportBaseName(fileURL: url, log: ContestLog(partyID: "ksqp")),
            "2026-08-29 KSQP KE5CW"
        )
    }

    /// ...and an unsaved draft exports under the same dated name the
    /// first auto-save is about to give its file.
    func testExportBaseNameForADraftMatchesItsFutureFileName() {
        var log = ContestLog(partyID: "moqp")
        log.station.callsign = "KE5CW"
        log.qsos = [
            QSO(
                timestampUTC: Date(timeIntervalSince1970: 1_788_013_920),  // 2026-08-29Z
                call: "W0AAA",
                band: .m20,
                modeClass: .cw,
                rawMode: "CW",
                rstSent: "599",
                rstRcvd: "599",
                myLoc: "ADR",
                theirLoc: "SED"
            )
        ]
        XCTAssertEqual(
            LogDocument.exportBaseName(fileURL: nil, log: log),
            "2026-08-29 MOQP KE5CW"
        )
    }

    // MARK: The spot-use fact (2026-07-28)

    /// A spot delivered into the session is recorded on the document — once.
    /// The method takes no undo manager on purpose: this is an observation,
    /// not an operator edit, and ⌘Z must never clear an integrity record.
    @MainActor
    func testNoteSpotsUsedRecordsTheFactOnce() {
        let doc = LogDocument()
        XCTAssertFalse(doc.log.usedSpots, "precondition: a fresh document has used nothing")

        doc.noteSpotsUsed()
        XCTAssertTrue(doc.log.usedSpots)

        doc.noteSpotsUsed()  // the thousandth spot says nothing the first didn't
        XCTAssertTrue(doc.log.usedSpots)
    }

    // MARK: Bulk row edits are one undoable step (2026-08-05)

    @MainActor
    func bulkDocument(count: Int) -> LogDocument {
        let doc = LogDocument()
        doc.log.qsos = (0..<count).map { index in
            QSO(
                call: "W\(index)AW", band: .m40, modeClass: .cw, rawMode: "CW",
                rstSent: "599", rstRcvd: "599", myLoc: "JOH", theirLoc: "TX"
            )
        }
        return doc
    }

    /// The whole point of a bulk change is that it touches many rows, so undo
    /// has to give them all back at once. Fifteen `update(qso:)` calls would
    /// cost fifteen ⌘Z presses.
    @MainActor
    func testABulkChangeUndoesInOneStep() {
        let undo = UndoManager()
        let doc = bulkDocument(count: 5)
        let moved = doc.log.qsos.map { row -> QSO in
            var row = row
            row.band = .m20
            return row
        }

        doc.update(qsos: moved, actionName: "Change 5 Contacts", undoManager: undo)
        XCTAssertEqual(doc.log.qsos.map(\.band), Array(repeating: .m20, count: 5))
        XCTAssertEqual(undo.undoActionName, "Change 5 Contacts")

        undo.undo()
        XCTAssertEqual(
            doc.log.qsos.map(\.band), Array(repeating: .m40, count: 5),
            "one undo restores every row the change touched"
        )

        undo.redo()
        XCTAssertEqual(doc.log.qsos.map(\.band), Array(repeating: .m20, count: 5))
    }

    /// Only the rows handed in move. A bulk change is a selection, not the log.
    @MainActor
    func testABulkChangeLeavesUnselectedRowsAlone() {
        let doc = bulkDocument(count: 3)
        var first = doc.log.qsos[0]
        first.myLoc = "MIA"

        doc.update(qsos: [first], actionName: "Change 1 Contact", undoManager: nil)
        XCTAssertEqual(doc.log.qsos.map(\.myLoc), ["MIA", "JOH", "JOH"])
    }

    /// A row deleted while the sheet was open is simply not written — undo of
    /// a deletion is `append`'s job, and resurrecting it here would make a
    /// bulk edit quietly undo someone else's delete.
    @MainActor
    func testARowNoLongerInTheLogIsNotResurrected() {
        let doc = bulkDocument(count: 2)
        var stale = doc.log.qsos[0]
        doc.remove(ids: [stale.id], undoManager: nil)
        stale.band = .m20

        doc.update(qsos: [stale], actionName: "Change 1 Contact", undoManager: nil)
        XCTAssertEqual(doc.log.qsos.count, 1)
        XCTAssertFalse(doc.log.qsos.contains { $0.id == stale.id })
    }

    @MainActor
    func testUpdateStationPersistsAndUndoesMyParks() {
        let doc = LogDocument()
        let undo = UndoManager()
        doc.updateStation(
            StationProfile(callsign: "KE5CW"),
            location: .outOfState(location: "TX"),
            partyID: "ksqp",
            myPotaRefs: ["US-3315"],
            undoManager: undo
        )
        XCTAssertEqual(doc.log.myPotaRefs, ["US-3315"])
        undo.undo()
        XCTAssertEqual(doc.log.myPotaRefs, [])
    }
}
