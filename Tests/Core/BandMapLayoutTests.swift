import XCTest
@testable import QSOPartyLogger

/// Column stacking for colliding band map labels.
final class BandMapLayoutTests: XCTestCase {

    private func spot(_ call: String, _ freqKHz: Double) -> Spot {
        Spot(
            call: call,
            freqKHz: freqKHz,
            spotter: "W3LPL",
            comment: "",
            receivedAt: Date(timeIntervalSince1970: 1_785_078_000)
        )
    }

    /// 14000–14350 over 350 pt, so 1 kHz is 1 pt and the arithmetic is legible.
    private let scale = BandMapScale(band: .m20, centerKHz: nil, spanKHz: 10_000)
    private let height: Double = 350

    private func place(
        _ spots: [Spot],
        rowHeight: Double = 13,
        columnWidth: Double = 60,
        availableWidth: Double = 180
    ) -> [BandMapLayout.Placement] {
        BandMapLayout.place(
            spots: spots,
            scale: scale,
            height: height,
            rowHeight: rowHeight,
            columnWidth: columnWidth,
            availableWidth: availableWidth
        )
    }

    // MARK: Ordering and true position

    func testSpotsRunHighFrequencyFirst() {
        let rows = place([spot("LOW", 14020), spot("HIGH", 14300), spot("MID", 14150)])
        XCTAssertEqual(rows.map(\.spot.call), ["HIGH", "MID", "LOW"])
    }

    /// Nothing collides, so every label sits on its own frequency in column 0.
    func testWellSpacedSpotsKeepTrueFrequencyInOneColumn() {
        let rows = place([spot("A", 14300), spot("B", 14200), spot("C", 14100)])
        XCTAssertEqual(rows.map(\.column), [0, 0, 0])
        XCTAssertEqual(rows[0].y, scale.y(forKHz: 14300, height: height), accuracy: 0.001)
        XCTAssertEqual(rows[1].y, scale.y(forKHz: 14200, height: height), accuracy: 0.001)
        XCTAssertEqual(rows[2].y, scale.y(forKHz: 14100, height: height), accuracy: 0.001)
    }

    // MARK: Collisions go sideways, not down

    func testCollidingSpotsFanOutToTheRightAtTheirTrueFrequency() {
        let rows = place([spot("A", 14300), spot("B", 14299), spot("C", 14298)])
        XCTAssertEqual(rows.map(\.column), [0, 1, 2], "each collision takes the next column")
        for row in rows {
            XCTAssertEqual(
                row.y, scale.y(forKHz: row.spot.freqKHz, height: height), accuracy: 0.001,
                "\(row.spot.call) stays on its own frequency"
            )
        }
    }

    /// The whole point: a pile-up no longer drags later labels off frequency.
    /// The old push-down put BELOW at 50 + 3×13 = 89 pt; its frequency is 70.
    func testASpotBelowAPileUpIsNotPushedDown() throws {
        let rows = place([
            spot("A", 14300), spot("B", 14299), spot("C", 14298), spot("BELOW", 14280),
        ])
        let below = try XCTUnwrap(rows.last)
        XCTAssertEqual(below.spot.call, "BELOW")
        XCTAssertEqual(below.y, scale.y(forKHz: 14280, height: height), accuracy: 0.001)
        XCTAssertEqual(below.column, 0)
    }

    func testColumnZeroIsReusedOnceThePileUpIsPassed() {
        // 14300/14299/14298 collide; 14285 clears 14300 by 15 pt (> rowHeight).
        let rows = place([
            spot("A", 14300), spot("B", 14299), spot("C", 14298), spot("D", 14285),
        ])
        XCTAssertEqual(rows.map(\.column), [0, 1, 2, 0], "D returns to the leftmost column")
    }

    /// Columns fill and free independently: at y = 70, column 0 is blocked by D
    /// at 65 but column 1 has been clear since B at 51, so E belongs there.
    func testLeftmostAvailableColumnWins() {
        let rows = place([
            spot("A", 14300),   // y 50 → column 0
            spot("B", 14299),   // y 51 → collides, column 1
            spot("D", 14285),   // y 65 → column 0 is free again
            spot("E", 14280),   // y 70 → column 0 blocked by D, column 1 free
        ])
        XCTAssertEqual(rows.map(\.column), [0, 1, 0, 1])
    }

    // MARK: Width

    func testNarrowPanelAllowsFewerColumns() {
        let rows = place(
            [spot("A", 14300), spot("B", 14299), spot("C", 14298)],
            availableWidth: 120  // room for two columns
        )
        XCTAssertEqual(rows.map(\.column), [0, 1, 1])
    }

    func testPanelTooNarrowForEvenOneColumnStillPlacesInColumnZero() {
        let rows = place([spot("A", 14300), spot("B", 14299)], availableWidth: 10)
        XCTAssertEqual(rows.map(\.column), [0, 0])
    }

    // MARK: Overflow

    /// When every column is busy the last one pushes down rather than dropping
    /// the spot — a deep pile-up still shows every call.
    func testOverflowPushesDownInTheLastColumnAndKeepsEveryCall() {
        let calls = ["A", "B", "C", "D", "E", "F"]
        let rows = place(calls.enumerated().map { spot($0.element, 14300 - Double($0.offset)) })

        XCTAssertEqual(rows.count, calls.count, "no spot is dropped")
        XCTAssertEqual(Set(rows.map(\.spot.call)), Set(calls))
        XCTAssertEqual(rows.map(\.column), [0, 1, 2, 2, 2, 2])

        let overflow = rows.filter { $0.column == 2 }.map(\.y)
        for (earlier, later) in zip(overflow, overflow.dropFirst()) {
            XCTAssertGreaterThanOrEqual(later - earlier, 13, "overflow keeps a full row of clearance")
        }
    }

    func testEverySpotOnOneFrequencyIsStillPlaced() {
        let calls = (0..<20).map { "K\($0)AA" }
        let rows = place(calls.map { spot($0, 14200) })
        XCTAssertEqual(rows.count, 20)
        XCTAssertEqual(Set(rows.map(\.spot.call)).count, 20)
    }

    // MARK: Windowing

    func testSpotsOutsideTheVisibleWindowAreDropped() {
        let zoomed = BandMapScale(band: .m20, centerKHz: 14040, spanKHz: 50)
        let rows = BandMapLayout.place(
            spots: [spot("IN", 14040), spot("HIGH", 14300), spot("LOW", 14005)],
            scale: zoomed,
            height: height,
            rowHeight: 13,
            columnWidth: 60,
            availableWidth: 180
        )
        XCTAssertEqual(rows.map(\.spot.call), ["IN"])
    }

    func testEmptyInputPlacesNothing() {
        XCTAssertTrue(place([]).isEmpty)
    }
}
