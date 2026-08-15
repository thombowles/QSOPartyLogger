import Foundation

/// Where phone keys get their audio, on a radio that offers both. Raw values
/// are UserDefaults storage, never display (Article 10 practice — the picker
/// supplies its own neutral wording).
enum PhoneMessageSource: String, Codable, CaseIterable, Sendable {
    /// Recordings on this Mac, played to the radio — the default.
    case recordings
    /// The radio's own recorder.
    case radioMemories
}

/// How the sound-card path keys the radio. Not consulted by a radio that takes
/// the audio over its own link — that driver keys itself.
enum VoicePTTMode: String, Codable, CaseIterable, Sendable {
    /// `TX;`/`RX;` (or the maker's equivalent) over CAT — the default.
    case radioCommand
    /// Nothing: the radio's VOX keys on the audio.
    case vox
}
