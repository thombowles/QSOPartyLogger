import Foundation

/// A CAT radio driver. Implement this (and register in `RadioRegistry`) to add
/// support for a new radio — nothing else in the app changes.
protocol RadioDriver: AnyObject {
    /// Attach to an open transport and begin polling.
    func start(transport: any SerialTransport)
    func stop()

    /// Latest state pushed here (background queue).
    var onStateChange: (@Sendable (RadioState) -> Void)? { get set }
    /// Radio-side keyer speed changes (front-panel knob), for speed sync.
    var onKeyerSpeedChange: (@Sendable (Int) -> Void)? { get set }

    func setFrequency(hz: Int)
    /// ADIF-style mode ("CW", "SSB", "USB", "RTTY"…). Drivers resolve "SSB"
    /// to the conventional sideband for the current frequency.
    func setMode(rawMode: String)
    /// Sets the *radio's own* keyer speed. Every radio implements it: even one
    /// the app keys directly needs its paddles and front-panel display to show
    /// the same number the app does (Article 11).
    func setKeyerSpeed(wpm: Int)
}

/// A radio with no control lines to key from, which therefore sends CW through
/// its own keyer — Flex CWX today.
///
/// This is deliberately *not* part of `RadioDriver`. A radio that exposes key
/// lines is keyed directly and only directly (Article 11), so on those drivers
/// these methods would have no caller and no meaning, and Article 13 forbids
/// stubbing a protocol member you do not honour. Conforming is the driver's
/// declaration that this radio has no other way to send.
protocol InternalKeyerDriver: RadioDriver {
    /// Send text through the radio's own keyer.
    func sendInternalKeyerText(_ text: String)
    func stopInternalKeyer()
}
