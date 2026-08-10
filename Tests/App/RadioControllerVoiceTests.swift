import XCTest
@testable import QSOPartyLogger

/// `RadioController`'s voice-memory glue: the observable state a driver's
/// callbacks feed, the badge bookkeeping shared with CW, and the two ways a
/// requested play can go nowhere. No transport answers here — connecting
/// against `/dev/null` (as `RadioControllerConnectionTests` does) is enough to
/// prove `isConnected` and wire a real `internalKeyer`, but a real K3 never
/// gets to speak, so `voiceStatus` never becomes ready on its own.
/// `voiceDidChangeStatus` and `voiceDidChangeBank` — the same kind of
/// directly-callable handler as `driverDidReportState` — stand in for the
/// driver's `OM` and `IC` bank reports, exactly as `driverDidReportState`
/// already stands in for its `IF` report in `RadioControllerConnectionTests`.
@MainActor
final class RadioControllerVoiceTests: XCTestCase {

    /// A K3 on a silent port, with `.radioInternal` selected so a CW send in
    /// these tests runs `ElecraftK3Driver.sendInternalKeyerText` — a
    /// synchronous write to the transport — rather than spinning up the
    /// direct keyer's real-time DTR/RTS thread.
    private func makeSettings() -> AppSettings {
        let settings = AppSettings(defaults: Preferences.store)
        settings.radioID = "elecraft-k3"
        settings.portPath = "/dev/null"
        settings.keyerBackend = .radioInternal
        return settings
    }

    // MARK: Defaults

    func testFreshControllerDefaultsToUnsupportedVoiceStatusAndNoBank() {
        let radio = RadioController()
        XCTAssertEqual(radio.voiceStatus, .unsupported)
        XCTAssertNil(radio.voiceBank)
    }

    // MARK: nowSendingIsVoice — the two paths must not clear each other's badge

    /// The regression `nowSendingIsVoice` exists to prevent: a voice memory
    /// goes out, then the operator sends CW before the radio confirms the
    /// memory finished. If `sendCW` forgot to hand the badge back, the radio's
    /// now-stale voice end-of-playback signal would wipe the CW badge out from
    /// under a transmission that is still in progress.
    func testVoiceEndOfPlaybackSignalDoesNotClearASubsequentCWBadge() {
        let settings = makeSettings()
        let radio = RadioController()
        radio.connect(settings: settings)
        defer { radio.disconnect() }

        // Simulate the driver confirming a K3 with a full 8-memory recorder —
        // the same effect `onVoiceKeyerStatusChange` has when a real `OM;`
        // arrives.
        radio.voiceDidChangeStatus(.available(count: 8))
        radio.playVoiceMessage(memory: 1, caption: "M1")
        XCTAssertEqual(radio.nowSending, "M1", "the voice send claims the badge")

        radio.sendCW("CQ TEST", settings: settings)
        XCTAssertEqual(radio.nowSending, "CQ TEST", "the CW send claims the badge next")

        // A late signal from the *voice* path — the radio finishing the
        // memory it played earlier — must not touch a badge the CW path now
        // owns.
        radio.voiceDidChangePlayback(false)
        XCTAssertEqual(
            radio.nowSending, "CQ TEST",
            "a stale voice end-of-playback signal must not clear the CW path's badge"
        )
    }

    /// The mirror image, pinned so the flag's meaning is unambiguous: when the
    /// voice path really does still own the badge, its own end-of-playback
    /// signal does clear it.
    func testVoiceEndOfPlaybackSignalClearsItsOwnBadge() {
        let settings = makeSettings()
        let radio = RadioController()
        radio.connect(settings: settings)
        defer { radio.disconnect() }

        radio.voiceDidChangeStatus(.available(count: 8))
        radio.playVoiceMessage(memory: 1, caption: "M1")
        XCTAssertEqual(radio.nowSending, "M1")

        radio.voiceDidChangePlayback(false)
        XCTAssertNil(radio.nowSending, "the voice path's own end-of-playback signal clears its badge")
    }

    /// The drop handler's mirror of the two tests above: a bank confirmation
    /// that finally times out well after a CW send claimed the badge must not
    /// wipe it either — the same mid-macro flicker the hold exists to
    /// prevent, reachable through the drop path instead of the playback path.
    func testUnconfirmedDropAfterASubsequentCWSendDoesNotClearTheCWBadge() {
        let settings = makeSettings()
        let radio = RadioController()
        radio.connect(settings: settings)
        defer { radio.disconnect() }

        radio.voiceDidChangeStatus(.available(count: 8))
        radio.playVoiceMessage(memory: 6, caption: "M6")
        XCTAssertEqual(radio.nowSending, "M6")

        radio.sendCW("CQ TEST", settings: settings)
        XCTAssertEqual(radio.nowSending, "CQ TEST")

        // M6's bank confirmation finally times out — long after CW took the
        // badge over. The drop belongs to a play nothing is waiting on
        // anymore.
        radio.voiceMessageWasDropped(6, .unconfirmed)
        XCTAssertEqual(radio.nowSending, "CQ TEST", "a stale drop must not clear a badge the CW path now owns")
    }

    // MARK: Dropped reasons — only one of the two is worth an error

    /// `.busy` means "the second press did nothing; the first is still on the
    /// air" — so the badge that press's own optimistic claim overwrote must
    /// come back, naming the play that is actually still running.
    func testBusyDropSetsNoErrorAndRestoresThePreviousBadge() {
        let settings = makeSettings()
        let radio = RadioController()
        radio.connect(settings: settings)
        defer { radio.disconnect() }

        radio.voiceDidChangeStatus(.available(count: 8))
        radio.playVoiceMessage(memory: 1, caption: "M1")
        XCTAssertEqual(radio.nowSending, "M1", "the first play claims the badge")

        // A second press while the first is still in flight. This second
        // `playVoiceMessage` call is what captures "M1, still running" as
        // the snapshot to restore — exactly what happens for real, since a
        // driver only ever emits `.busy` from inside a *new*
        // `playVoiceMessage(memory:)` call it is refusing to act on.
        radio.playVoiceMessage(memory: 2, caption: "M2")
        XCTAssertEqual(radio.nowSending, "M2", "the second press optimistically claims the badge too")

        radio.voiceMessageWasDropped(2, .busy)
        XCTAssertNil(radio.lastError, "a double-tap while a play is in flight is ordinary, not a fault")
        XCTAssertEqual(radio.nowSending, "M1", "a busy refusal restores the play that is still actually running")
    }

    func testUnconfirmedDropSetsAnErrorNamingTheMemory() {
        let settings = makeSettings()
        let radio = RadioController()
        radio.connect(settings: settings)
        defer { radio.disconnect() }

        radio.voiceDidChangeStatus(.available(count: 8))
        radio.playVoiceMessage(memory: 3, caption: "M3")
        XCTAssertEqual(radio.nowSending, "M3")

        radio.voiceMessageWasDropped(3, .unconfirmed)
        XCTAssertNil(radio.nowSending, "the badge the drop belongs to is cleared")
        XCTAssertEqual(radio.lastError?.summary, "Voice memory not sent")
        XCTAssertEqual(radio.lastError?.detail.contains("M3"), true, "detail names the dropped memory")
    }

    // MARK: Disconnect must silence every voice handler, not just clear state once

    /// The sharpest form of the guard: a bank confirmation that times out
    /// after the operator has already disconnected must not overwrite
    /// `transportDidDisconnect`'s real "Connection lost" story with a stale
    /// "Voice memory not sent" of its own.
    func testUnconfirmedDropAfterDisconnectDoesNotOverwriteTheConnectionLostError() {
        let radio = RadioController()
        radio.connect(settings: makeSettings())
        radio.transportDidDisconnect(reason: "Connection reset by peer")
        XCTAssertEqual(radio.lastError?.summary, "Connection lost")

        radio.voiceMessageWasDropped(3, .unconfirmed)
        XCTAssertEqual(
            radio.lastError?.summary, "Connection lost",
            "a stale drop arriving after disconnect must not overwrite the real story"
        )
    }

    func testVoiceDidChangeStatusIsIgnoredWhileDisconnected() {
        let radio = RadioController()
        radio.voiceDidChangeStatus(.available(count: 8))
        XCTAssertEqual(radio.voiceStatus, .unsupported, "a disconnected controller ignores a late status report")
    }

    func testVoiceDidChangePlaybackIsIgnoredWhileDisconnected() {
        let radio = RadioController()
        radio.voiceDidChangePlayback(true)
        XCTAssertFalse(radio.isVoicePlaying, "a disconnected controller ignores a late playback report")
    }

    func testVoiceDidChangeBankSetsBankOnlyWhileConnected() {
        let radio = RadioController()
        radio.voiceDidChangeBank(2)
        XCTAssertNil(radio.voiceBank, "a disconnected controller ignores a late bank report")

        let settings = makeSettings()
        radio.connect(settings: settings)
        defer { radio.disconnect() }
        radio.voiceDidChangeBank(2)
        XCTAssertEqual(radio.voiceBank, 2)
    }

    // MARK: abortTransmission — the rename's whole point is that this covers voice too

    /// `abortTransmission` used to be `abortCW`; this is the behaviour the
    /// rename exists to describe honestly. `AppSettings(defaults:
    /// Preferences.store)` is the same safe construction
    /// `RadioControllerConnectionTests` already uses — the test bundle
    /// redirects `Preferences.store` to a throwaway suite before any test
    /// runs (`TestBundleSetup`), so this never touches the operator's real
    /// preferences.
    ///
    /// This only pins the one externally observable effect: the badge clears
    /// immediately rather than waiting on the radio's own signal.
    /// `voiceDriver?.stopVoiceMessage()` is a real call into a real (silent)
    /// `ElecraftK3Driver` here — proven harmless, not proven to have written
    /// `RX;`, since nothing in this suite can see what reached `/dev/null`.
    func testAbortTransmissionClearsAVoiceBadgeImmediately() {
        let settings = makeSettings()
        let radio = RadioController()
        radio.connect(settings: settings)
        defer { radio.disconnect() }

        radio.voiceDidChangeStatus(.available(count: 8))
        radio.playVoiceMessage(memory: 1, caption: "M1")
        XCTAssertEqual(radio.nowSending, "M1")

        radio.abortTransmission(settings: settings)
        XCTAssertNil(radio.nowSending, "Esc clears the badge immediately, not on the radio's own signal")
    }

    // MARK: playVoiceMessage's guard

    // `playVoiceMessage` while genuinely disconnected has no dedicated test:
    // `voiceStatus` can only ever be ready while connected (`voiceDidChangeStatus`
    // now shares the same `isConnected` guard, and `disconnect()` always resets
    // `voiceStatus` to `.unsupported` in the same synchronous call that clears
    // `isConnected`), so there is no way to construct "ready but disconnected"
    // through the controller's own testable surface — a test asserting nothing
    // happens while disconnected would pass purely because `voiceStatus.isReady`
    // is already false, and would keep passing even if the `isConnected` clause
    // were deleted from the guard. `testPlayVoiceMessageDoesNothingUnlessVoiceIsReady`
    // below is the one that can actually fail.

    func testPlayVoiceMessageDoesNothingUnlessVoiceIsReady() {
        let settings = makeSettings()
        let radio = RadioController()
        radio.connect(settings: settings)
        defer { radio.disconnect() }

        // `.unsupported` is the untouched default; `.notInstalled` and a
        // zero-count `.available` are the other two ways a radio can report
        // "nothing to play" — none of them may transmit.
        for status: VoiceKeyerStatus in [.unsupported, .notInstalled, .available(count: 0)] {
            radio.voiceDidChangeStatus(status)
            radio.playVoiceMessage(memory: 1, caption: "M1")
            XCTAssertNil(radio.nowSending, "\(status) is not ready — nothing should transmit")
        }
    }

    /// The controller owns the badge it is about to set and must not trust a
    /// caller's range check: a memory beyond what the radio reported would
    /// otherwise claim an untimed badge that nothing will ever clear, since
    /// the driver discards an out-of-range memory with no callback either way.
    func testPlayVoiceMessageWithAnOutOfRangeMemoryDoesNothing() {
        let settings = makeSettings()
        let radio = RadioController()
        radio.connect(settings: settings)
        defer { radio.disconnect() }

        // A KX-shaped radio: only memories 1-2 exist.
        radio.voiceDidChangeStatus(.available(count: 2))
        radio.playVoiceMessage(memory: 3, caption: "M3")
        XCTAssertNil(radio.nowSending, "a memory beyond what the radio reported must not claim the badge")
    }
}
