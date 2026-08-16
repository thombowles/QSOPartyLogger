import XCTest
@testable import QSOPartyLogger

/// The band map model must not mutate observable state while a view is reading
/// it.
///
/// `BandMapModel` is `@Observable`, so every stored property it writes
/// invalidates any view that read it. `isNeededMultiplier` is called from the
/// band map's body once per spot, and it memoises. If that memo is observable,
/// each render writes it, the write invalidates the view, and the view renders
/// again — SwiftUI spins until the stack is gone.
///
/// That is not theoretical: it crashed the app on 2026-07-25 with
/// `EXC_BAD_ACCESS`, "Thread stack size exceeded due to excessive recursion",
/// looping between `AppGraph.graphDidChange()` and `scenesDidChange`.
@MainActor
final class BandMapObservationTests: XCTestCase {

    private func model(party: PartyDefinition) -> BandMapModel {
        let model = BandMapModel(
            radio: RadioController(),
            spotStore: SpotStore(),
            settings: AppSettings.shared
        )
        model.party = party
        var log = ContestLog(partyID: party.id)
        log.myLocation = .outOfState(location: "TX")
        model.log = log
        model.allowedModes = party.allowedModeClasses
        return model
    }

    private func hubSpot(_ call: String, _ county: String, _ kHz: Double) -> Spot {
        Spot(call: call, freqKHz: kHz, spotter: "N4EMP", comment: "",
             receivedAt: Date(), county: county, source: .hub)
    }

    /// Reading the multiplier badge must leave the model observationally
    /// unchanged, however many spots are on the band.
    func testReadingTheMultiplierBadgeDoesNotInvalidateTheView() throws {
        let alqp = try XCTUnwrap(PartyCatalog.party(id: "alqp"))
        let model = model(party: alqp)

        final class Flag: @unchecked Sendable { var tripped = false }
        let invalidated = Flag()

        // Stand in for one render: read the badge for the spots on the band.
        withObservationTracking {
            _ = model.isNeededMultiplier(hubSpot("K4EES", "BALD", 7048))
            _ = model.isNeededMultiplier(hubSpot("N4UC", "MDSN", 14042.3))
        } onChange: {
            invalidated.tripped = true
        }

        // Then a new spot arrives, as one does every poll. Its badge has not
        // been asked for before, so this is the write that would close the
        // loop if the memo were observable.
        _ = model.isNeededMultiplier(hubSpot("WA1FCN/4", "WLKR", 7044.6))

        XCTAssertFalse(
            invalidated.tripped,
            "reading the badge invalidated the view — this is the render loop that crashed the app"
        )
    }

    /// The memo must still do its job: the same question gives the same answer.
    func testTheBadgeIsStableAcrossRepeatedReads() throws {
        let alqp = try XCTUnwrap(PartyCatalog.party(id: "alqp"))
        let model = model(party: alqp)
        let spot = hubSpot("K4EES", "BALD", 7048)

        let first = model.isNeededMultiplier(spot)
        XCTAssertTrue(first, "an unworked Baldwin County is a multiplier")
        XCTAssertEqual(model.isNeededMultiplier(spot), first)
        XCTAssertEqual(model.isNeededMultiplier(spot), first)
    }

    /// And it must not go stale: logging the county changes the answer.
    func testLoggingTheCountyClearsTheBadge() throws {
        let alqp = try XCTUnwrap(PartyCatalog.party(id: "alqp"))
        let model = model(party: alqp)
        let spot = hubSpot("K4EES", "BALD", 7048)
        XCTAssertTrue(model.isNeededMultiplier(spot))

        var log = try XCTUnwrap(model.log)
        log.qsos = [
            QSO(call: "K4EES", band: .m40, modeClass: .cw, rawMode: "CW",
                rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: "BALD")
        ]
        model.log = log

        XCTAssertFalse(model.isNeededMultiplier(spot),
                       "Baldwin is in the log now — the memo must have been dropped")
    }

    /// The same rule for the location memo behind a cluster spot's colour: the
    /// first read computes and stores it, and that store must not invalidate
    /// the view either.
    func testReadingAClusterSpotsColourDoesNotInvalidateTheView() throws {
        let alqp = try XCTUnwrap(PartyCatalog.party(id: "alqp"))
        let model = model(party: alqp)
        model.callHistory = CallHistoryFile.parse("""
        !!Order!!,Call,Name,Exch1,UserText,
        K4EES,,BALD,
        N4UC,,MDSN,
        """)
        let cluster = { (call: String, kHz: Double) in
            Spot(call: call, freqKHz: kHz, spotter: "W3LPL", comment: "", receivedAt: Date())
        }

        final class Flag: @unchecked Sendable { var tripped = false }
        let invalidated = Flag()

        withObservationTracking {
            _ = model.status(for: cluster("K4EES", 7030))
        } onChange: {
            invalidated.tripped = true
        }
        _ = model.status(for: cluster("N4UC", 7032))
        _ = model.status(for: cluster("WA1FCN", 7034))

        XCTAssertFalse(invalidated.tripped,
                       "classifying a spot invalidated the view — the render loop again")
    }
}
