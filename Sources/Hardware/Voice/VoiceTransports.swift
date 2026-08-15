import Foundation

/// A radio the app can key over its control link for the duration of a
/// message it plays through a sound card. `TX;`/`RX;` on the Elecraft family.
/// Nothing about the audio: that goes out a CoreAudio device the operator
/// picked. Conform in the driver, and only where the maker's reference
/// documents the on and off commands (Article 11).
///
/// `Sendable` because the player keys from its own thread, between the lead
/// and the first sample; every driver is `@unchecked Sendable` behind a lock,
/// and this is where that promise is stated.
protocol TransmitControlCapable: RadioDriver, Sendable {
    func setTransmit(_ on: Bool)
}

/// What a voice transport reports about one play. Exactly one terminal event
/// (`finished`, `stopped` or `failed`) per play; the radio is unkeyed before
/// any terminal event is reported.
enum TransmitAudioEvent: Equatable, Sendable {
    /// Audio has begun to go out.
    case started
    /// Played to the end; the radio is unkeyed.
    case finished
    /// Aborted; the radio is unkeyed.
    case stopped
    /// Never keyed, or unkeyed early. The text is shown to the operator.
    case failed(String)
}

/// A radio that takes transmit audio from the app over its own connection —
/// no sound card, no PTT line. The driver keys, streams, and unkeys, and it
/// reports each of those for real.
protocol AudioStreamTransmitCapable: RadioDriver {
    /// The rate the radio wants samples at. The caller resamples to it.
    var transmitSampleRate: Double { get }
    /// Key the radio, put `audio` on the air, unkey. One at a time: a second
    /// call while one is in flight stops the first.
    func transmitAudio(_ audio: VoiceAudio)
    func stopTransmitAudio()
    var onTransmitAudioEvent: (@Sendable (TransmitAudioEvent) -> Void)? { get set }
    /// What the driver said and heard on this path, most recent last — the
    /// commands it sent, the replies and status lines it acted on, packet
    /// counts, and each event. Shown to the operator on request so a
    /// message that keyed but did not modulate can be diagnosed from the
    /// radio's own words rather than guessed at.
    var transmitAudioTranscript: [String] { get }
}

/// The sound-card path: plays a clip to an output device and keys the radio
/// around it. A protocol so `RadioController` is tested against a fake.
protocol VoicePlaying: AnyObject {
    /// `deviceUID` nil = the system default output. `keyRadio`, when given, is
    /// called with `true` `leadMs` before the first sample and `false`
    /// `tailMs` after the last; nil means VOX — never key. `onEvent` fires
    /// `.started` when audio begins and one terminal event at the end.
    func play(_ audio: VoiceAudio, deviceUID: String?, gain: Float,
              keyRadio: (@Sendable (Bool) -> Void)?, leadMs: Int, tailMs: Int,
              onEvent: @escaping @Sendable (TransmitAudioEvent) -> Void)
    func stop()
}
