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
    func setKeyerSpeed(wpm: Int)
    /// Send text through the radio's internal keyer, if it has one.
    func sendInternalKeyerText(_ text: String)
    func stopInternalKeyer()
}
