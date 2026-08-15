import Foundation

/// One recording as the sidecar describes it. Non-destructive: the file is
/// what was recorded or imported; trim and gain apply at playback, so a trim
/// can be widened later and a normalize undone.
struct VoiceClip: Codable, Equatable, Sendable {
    /// Always relative to the set's folder — "M3.wav". Never an absolute
    /// path: the folder can move (a new Mac, a restored backup) and the set
    /// must still find its files.
    var fileName: String
    /// Of the whole file, so the row can show it without opening it.
    var duration: TimeInterval
    var trimStart: TimeInterval
    var trimEnd: TimeInterval
    /// 0 = as recorded. Normalize writes the gain that puts the peak at −1 dBFS.
    var gainDB: Float
    var recordedAt: Date

    var trimmedDuration: TimeInterval { max(0, trimEnd - trimStart) }
}

/// A party's memories, 1...`MessageSets.voiceMemorySlots`. A missing key is an
/// empty memory. Encoded with the memory number as the JSON object key
/// ("1": {…}) so the sidecar reads like the editor does — a `[Int: …]` would
/// encode as a flat array of alternating keys and values.
struct VoiceMessageSet: Equatable, Sendable {
    static let currentVersion = 1
    var version = VoiceMessageSet.currentVersion
    var clips: [Int: VoiceClip] = [:]

    subscript(memory: Int) -> VoiceClip? {
        get { clips[memory] }
        set { clips[memory] = newValue }
    }

    var recordedMemories: Set<Int> { Set(clips.keys) }
    var isEmpty: Bool { clips.isEmpty }
}

extension VoiceMessageSet: Codable {
    private enum CodingKeys: String, CodingKey { case version, clips }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        let keyed = try c.decodeIfPresent([String: VoiceClip].self, forKey: .clips) ?? [:]
        clips = Dictionary(uniqueKeysWithValues: keyed.compactMap { key, clip in
            Int(key).map { ($0, clip) }
        })
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(Dictionary(uniqueKeysWithValues: clips.map { (String($0.key), $0.value) }), forKey: .clips)
    }
}
