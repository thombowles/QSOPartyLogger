import Foundation

/// What the connected radio can do about recorded voice messages.
///
/// Runtime rather than a `RadioDescriptor` flag, because Article 11 requires
/// the count to be discovered from the radio: one descriptor's family answers
/// 8, 2 or 0 depending on the model and on whether an option module is fitted.
enum VoiceKeyerStatus: Equatable, Sendable {
    /// This radio has no voice memories the app can drive.
    case unsupported
    /// It has them, but the hardware that provides them is not fitted.
    case notInstalled
    /// Ready, with memories numbered 1...count.
    case available(count: Int)

    var memoryCount: Int {
        if case .available(let count) = self { max(0, count) } else { 0 }
    }

    /// Whether an F-key may transmit. A zero-count `.available` is not ready:
    /// there is nothing to play.
    var isReady: Bool { memoryCount > 0 }
}

/// A radio that can play its own recorded voice messages.
///
/// A separate protocol rather than more `RadioDriver` members with no-op
/// defaults. Article 11 forbids stubbing out the *CW* keyer members because
/// both keying paths exist on every serial radio and the operator may prefer
/// either. A recorder is different in kind: a radio without one has nothing to
/// stub, and an empty implementation would let it claim a capability by
/// silence. `RadioController` tests for conformance instead.
protocol VoiceMessageCapable: RadioDriver {
    /// Play the radio's own recording in `memory` (1-based). A memory this
    /// radio does not have is ignored, never clamped onto a neighbour.
    func playVoiceMessage(memory: Int)
    /// Stop playback immediately.
    func stopVoiceMessage()
    /// What the radio turned out to be able to do, once asked.
    var onVoiceKeyerStatusChange: (@Sendable (VoiceKeyerStatus) -> Void)? { get set }
    /// True while the radio reports a message actually playing — a real signal,
    /// not an estimate.
    var onVoicePlaybackChange: (@Sendable (Bool) -> Void)? { get set }
    /// A play that could not be carried out safely, and so was not carried out
    /// at all. Carries the memory that was asked for. Nothing was transmitted.
    var onVoiceMessageDropped: (@Sendable (Int) -> Void)? { get set }
    /// The message bank the radio was last *observed* in, on radios that have
    /// banks. Radios without them never fire it, so the UI shows nothing.
    /// Reported because the app leaves the bank where the last play put it,
    /// which changes what the front panel's own buttons address.
    var onVoiceBankChange: (@Sendable (Int) -> Void)? { get set }
}
