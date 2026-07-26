import XCTest
@testable import QSOPartyLogger

/// The band map's spot label presets, and the geometry each one carries.
///
/// A label size is never only a font size. The column pitch, the row clearance
/// and the centring offset are all statements about how wide and how tall a
/// callsign is drawn — grow the font without them and labels overlap. These
/// tests hold all four presets to that.
final class SpotLabelSizeTests: XCTestCase {

    /// The default has to render exactly what `BandMapView` hardcoded before
    /// the setting existed, so an operator who never opens the popover sees no
    /// pixel move. These six numbers came off `BandMap.swift` at 973aad6.
    func testSmallReproducesTheOriginalHardcodedGeometry() {
        let small = SpotLabelSize.small
        XCTAssertEqual(small.callPointSize, 10, "call font")
        XCTAssertEqual(small.countyPointSize, 8, "county badge font")
        XCTAssertEqual(small.columnWidth, 60, "column pitch")
        XCTAssertEqual(small.rowHeight, 13, "row clearance")
        XCTAssertEqual(small.verticalOffset, 6, "centring offset")
        XCTAssertEqual(small.minimumPanelWidth, 190, "panel minimum width")
    }

    func testSmallIsTheFirstCaseSoItIsTheLeftmostSegment() {
        XCTAssertEqual(SpotLabelSize.allCases.first, .small)
    }

    /// Nothing may grow the font while leaving the geometry flat — that is
    /// precisely how labels start colliding.
    func testEveryDimensionGrowsWithThePreset() {
        for (smaller, bigger) in zip(SpotLabelSize.allCases, SpotLabelSize.allCases.dropFirst()) {
            let step = "\(smaller.rawValue) → \(bigger.rawValue)"
            XCTAssertGreaterThan(bigger.callPointSize, smaller.callPointSize, "call font, \(step)")
            XCTAssertGreaterThan(bigger.countyPointSize, smaller.countyPointSize, "county font, \(step)")
            XCTAssertGreaterThan(bigger.columnWidth, smaller.columnWidth, "column pitch, \(step)")
            XCTAssertGreaterThan(bigger.rowHeight, smaller.rowHeight, "row clearance, \(step)")
            XCTAssertGreaterThan(bigger.verticalOffset, smaller.verticalOffset, "centring offset, \(step)")
        }
    }

    /// Why `minimumPanelWidth` exists at all. A single column sends every
    /// collision into `BandMapLayout`'s push-down branch, dragging labels off
    /// their true frequency — the failure sideways stacking was built to avoid.
    func testEveryPresetLeavesRoomForTwoColumnsAtItsMinimumWidth() {
        for size in SpotLabelSize.allCases {
            let labelArea = size.minimumPanelWidth
                - BandMapMetrics.rulerWidth - BandMapMetrics.labelInset
            XCTAssertGreaterThanOrEqual(
                Int(labelArea / size.columnWidth), 2,
                "\(size.rawValue) has room for only one label column at its minimum panel width"
            )
        }
    }

    /// The centring offset is half a row of clearance, less a half point — the
    /// relation the original `- 6` against a 13 pt row already encoded.
    func testTheCentringOffsetIsHalfTheRowClearance() {
        for size in SpotLabelSize.allCases {
            XCTAssertEqual(size.verticalOffset, size.rowHeight / 2 - 0.5, accuracy: 0.001,
                           "\(size.rawValue)")
        }
    }

    // MARK: Persistence and presentation

    /// The raw values are the persisted UserDefaults tokens, so they have to
    /// survive a round trip unchanged.
    func testRawValuesRoundTrip() {
        for size in SpotLabelSize.allCases {
            XCTAssertEqual(SpotLabelSize(rawValue: size.rawValue), size)
        }
    }

    func testEveryPresetHasADistinctSegmentLabel() {
        let labels = SpotLabelSize.allCases.map(\.segmentLabel)
        XCTAssertEqual(Set(labels).count, SpotLabelSize.allCases.count, "\(labels)")
    }

    func testEveryPresetHasADistinctDisplayName() {
        let names = SpotLabelSize.allCases.map(\.displayName)
        XCTAssertEqual(Set(names).count, SpotLabelSize.allCases.count, "\(names)")
    }
}
