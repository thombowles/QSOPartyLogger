import XCTest
@testable import QSOPartyLogger

/// What "SSB" resolves to before it reaches a driver. The typed command and
/// the band plan both say "SSB"; the sideband is the convention for the
/// frequency the radio is *about* to be on. A QSY's mode command lands right
/// behind its FA on the same wire — the K3 reference's macro notes spell out
/// that ordering ("MD is sent after it, so the mode change will apply to the
/// new band") — while the polled frequency still reads the old band. 40 m
/// went USB exactly that way (2026-08-29): QSY from 20 m CW to 7188, "SSB"
/// resolved against the stale 14 MHz poll.
@MainActor
final class RadioControllerModeTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    /// The bug: mid-QSY, the just-commanded target decides, not the stale
    /// poll — the same precedence a nudge gives (`nudgeBase`).
    func testSSBResolvesAgainstAJustCommandedTargetNotTheStalePoll() {
        XCTAssertEqual(
            RadioController.resolvedRawMode(
                "SSB", commandedHz: 7_188_000, commandedAt: t0,
                polledHz: 14_030_000, now: t0.addingTimeInterval(0.1)),
            "LSB"
        )
    }

    func testSSBFollowsThePolledFrequencyWhenNothingWasCommanded() {
        XCTAssertEqual(
            RadioController.resolvedRawMode(
                "SSB", commandedHz: nil, commandedAt: nil,
                polledHz: 7_030_000, now: t0),
            "LSB"
        )
        XCTAssertEqual(
            RadioController.resolvedRawMode(
                "SSB", commandedHz: nil, commandedAt: nil,
                polledHz: 14_200_000, now: t0),
            "USB"
        )
    }

    /// After `nudgeWindow` the knob may have moved: the poll speaks again.
    func testAnOldCommandIsOutrankedByAFreshPoll() {
        XCTAssertEqual(
            RadioController.resolvedRawMode(
                "SSB", commandedHz: 7_188_000, commandedAt: t0,
                polledHz: 14_200_000, now: t0.addingTimeInterval(5)),
            "USB"
        )
    }

    /// No frequency known at all: pass "SSB" through — the driver's own
    /// fallback owns that guess, exactly as before.
    func testSSBPassesThroughWhenNoFrequencyIsKnown() {
        XCTAssertEqual(
            RadioController.resolvedRawMode(
                "SSB", commandedHz: nil, commandedAt: nil, polledHz: nil, now: t0),
            "SSB"
        )
    }

    /// An explicit sideband — and every other mode — is the operator's word,
    /// never rewritten.
    func testOnlySSBIsResolved() {
        XCTAssertEqual(
            RadioController.resolvedRawMode(
                "LSB", commandedHz: 14_200_000, commandedAt: t0, polledHz: nil, now: t0),
            "LSB"
        )
        XCTAssertEqual(
            RadioController.resolvedRawMode(
                "USB", commandedHz: 7_188_000, commandedAt: t0, polledHz: nil, now: t0),
            "USB"
        )
        XCTAssertEqual(
            RadioController.resolvedRawMode(
                "CW", commandedHz: 7_188_000, commandedAt: t0, polledHz: nil, now: t0),
            "CW"
        )
    }

    /// 60 m: USB despite being below 10 MHz — the channels are USB by rule.
    func testSixtyMeterCommandResolvesUSB() {
        XCTAssertEqual(
            RadioController.resolvedRawMode(
                "SSB", commandedHz: 5_357_000, commandedAt: t0, polledHz: nil, now: t0),
            "USB"
        )
    }
}
