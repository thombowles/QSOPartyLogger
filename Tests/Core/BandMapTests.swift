import XCTest
@testable import QSOPartyLogger

/// Frequency↔pixel mapping for the band map window.
final class BandMapTests: XCTestCase {

    func testCenteredWindowInsideBand() {
        let s = BandMapScale(band: .m20, centerKHz: 14100, spanKHz: 50)
        XCTAssertEqual(s.lowKHz, 14075, accuracy: 0.01)
        XCTAssertEqual(s.highKHz, 14125, accuracy: 0.01)
    }

    func testClampsAtBandEdges() {
        let low = BandMapScale(band: .m20, centerKHz: 14005, spanKHz: 50)
        XCTAssertEqual(low.lowKHz, 14000, accuracy: 0.01)
        XCTAssertEqual(low.highKHz, 14050, accuracy: 0.01)

        let high = BandMapScale(band: .m20, centerKHz: 14340, spanKHz: 50)
        XCTAssertEqual(high.lowKHz, 14300, accuracy: 0.01)
        XCTAssertEqual(high.highKHz, 14350, accuracy: 0.01)
    }

    func testFullBandWhenSpanExceedsWidth() {
        let s = BandMapScale(band: .m20, centerKHz: 14042, spanKHz: 10_000)
        XCTAssertEqual(s.lowKHz, 14000, accuracy: 0.01)
        XCTAssertEqual(s.highKHz, 14350, accuracy: 0.01)
    }

    func testNilCenterUsesBandMiddle() {
        let s = BandMapScale(band: .m20, centerKHz: nil, spanKHz: 50)
        XCTAssertEqual(s.lowKHz, 14150, accuracy: 0.01)
        XCTAssertEqual(s.highKHz, 14200, accuracy: 0.01)
    }

    func testYMappingTopIsHighFrequency() {
        let s = BandMapScale(band: .m20, centerKHz: 14025, spanKHz: 50)
        XCTAssertEqual(s.y(forKHz: s.highKHz, height: 500), 0, accuracy: 0.01)
        XCTAssertEqual(s.y(forKHz: s.lowKHz, height: 500), 500, accuracy: 0.01)
        XCTAssertEqual(s.y(forKHz: (s.lowKHz + s.highKHz) / 2, height: 500), 250, accuracy: 0.01)
    }

    func testYToFrequencyRoundTrip() {
        let s = BandMapScale(band: .m40, centerKHz: 7040, spanKHz: 50)
        let kHz = s.kHz(atY: 125, height: 500)
        XCTAssertEqual(s.y(forKHz: kHz, height: 500), 125, accuracy: 0.01)
    }

    func testTicksAreNiceRoundNumbers() {
        let s = BandMapScale(band: .m20, centerKHz: 14100, spanKHz: 50)
        // 50 kHz span → 10 kHz ticks aligned to multiples of 10.
        XCTAssertEqual(s.tickKHz(), [14080, 14090, 14100, 14110, 14120])

        let full = BandMapScale(band: .m20, centerKHz: nil, spanKHz: 10_000)
        // 350 kHz span → 50 kHz ticks.
        XCTAssertEqual(full.tickKHz(), [14000, 14050, 14100, 14150, 14200, 14250, 14300, 14350])
    }
}
